---
title: "Some Approaches To Single-Process, Durable Queueing"
categories:
  - Programming
  - Golang
date: 2021-01-18 17:44:23
---

# Get in Line

As computer professionals, queuing is something that's close to most of us. After all, from the bottom up -- from CPU instructions to network packets to async reactor calls -- things get in line.

There are lots of queuing approaches in computer science and in life in general; as a result, we're only going to talk about a specific subclass of queues: durable ones that specifically _are not_ distributed amongst multiple hosts. These tend to be great models for smaller systems that do not need the overhead, complexity or reliability problems that distributed queues have.

# Some options before you dive in

So, this is an exploratory mission; while many of these patterns are in use in production scenarios, you may be looking for something more like the following software if you need to solve this problem:

- [NATS](https://nats.io)
- [Kafka](https://kafka.apache.org)
- [Redis](https://redis.io)

However, if you specifically need to solve the problem covered in this article, you will find there are no good solutions out there that easily resolve your issue. I could release `boltqueue` (below) as a library but I feel it's more useful as a pattern than an actual thing you code against.

# Explain Queues to Me Like I'm Five

Ok, you didn't ask for this but that's what the table of contents (lower left opens the sidebar) is for. :)

A queue is a line; at the end of the line things are inserted, and at the beginning of the line things are removed. These are called the "tail" and "head" respectively. Inserting is called a "enqueue", and removing is called a "dequeue".

## The most basic thread-safe queue

In golang, a basic queue can be modeled as an array with a mutex (a lock that only allows one thing to run at a time), like so:

```go
package main

import (
	"errors"
	"fmt"
	"sync"
)

var errQueueEmpty = errors.New("queue is empty")

type queue struct {
	items []item
	mutex sync.Mutex
}

type item interface{} // replace with your own type

func (q *queue) enqueue(i item) {
	// lock our mutex before performing any operations; unlock after the return
	// with defer
	q.mutex.Lock()
	defer q.mutex.Unlock()

	q.items = append(q.items, i)
}

func (q *queue) dequeue() (item, error) {
	q.mutex.Lock()
	defer q.mutex.Unlock()

	// return an error if the queue is empty, to disambiguate it from nils
	if len(q.items) == 0 {
		return nil, errQueueEmpty
	}

	// take the first item and dequeue the array or overwrite it if there's only
	// one item
	i := q.items[0]
	if len(q.items) > 0 {
		q.items = q.items[1:]
	} else {
		q.items = []item{}
	}

	return i, nil
}

func main() {
	q := &queue{}
	done := make(chan struct{})

	// start a goroutine to evaculate the queue while filling it concurrently
	go func() {
		defer close(done)

		var i interface{}

		for ok := true; ok; _, ok = i.(int) {
			var err error
			i, err = q.dequeue()
			if err != nil {
				return
			}

			fmt.Println(i)
		}
	}()

	for i := 0; i < 10000; i++ {
		q.enqueue(i)
	}

	<-done
}
```

## Channels

An even easier solution in Golang specifically is _channels_. Channels are the language construction of a queue which can be shared without copying its data.

Here's a solution that uses channels:

```go
package main

import "fmt"

func main() {
	intChan := make(chan int, 10000)
	done := make(chan struct{})

	// start a goroutine to evaculate the queue while filling it concurrently
	go func() {
		defer close(done)
		for i := range intChan {
			fmt.Println(i)
		}
	}()

	for i := 0; i < 10000; i++ {
		intChan <- i
	}

	close(intChan)
	<-done
}
```

Simpler, and much faster given the runtime's direct involvement.

# So, wait, you said something about durable?

Yes, I did! You may have noticed that your queue always starts at `0` and counts up to `9999`. _Durable_ queuing enables us to start at `10000` and work upwards as we encounter new data, between process restarts. Naturally, this involves databases of some form.

## The filesystem is a database, right?

Yes, it is, but not without its shortcomings in this regard. Here's an approach that appears to work, but probably won't if the disk fills or becomes unavailable. POSIX filesystem architecture was not very well-suited to fulfill this need. That said, many local mail clients interact with filesystem queues via the "Maildir" format, which is essentially a queue.

Here's a contender for such a queue:

```go
package main

import (
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"sync"
	"time"
)

type fnInts []uint64

// conform to sort.Interface

func (f fnInts) Len() int {
	return len(f)
}

func (f fnInts) Less(i, j int) bool {
	return f[i] < f[j]
}

func (f fnInts) Swap(i, j int) {
	f[i], f[j] = f[j], f[i]
}

var errQueueEmpty = errors.New("queue is empty")

type queue struct {
	dir   string
	first uint64
	last  uint64
	mutex sync.Mutex
}

type item []byte

func newQueue(dir string) (*queue, error) {
	fis, err := ioutil.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	files := []string{}

	for _, fi := range fis {
		files = append(files, path.Base(fi.Name()))
	}

	q := &queue{dir: dir}

	fnints := fnInts{}

	// sort the files; then use the filenames to calculate first/last positions
	for _, file := range files {
		fint, err := strconv.ParseUint(file, 10, 64)
		if err != nil {
			return nil, err
		}

		fnints = append(fnints, fint)
	}

	if len(fnints) > 0 {
		sort.Sort(fnints)

		q.first = fnints[0] - 1
		q.last = fnints[len(fnints)-1]
	}

	return q, nil
}

func (q *queue) dequeue() ([]byte, error) {
	q.mutex.Lock()
	defer q.mutex.Unlock()

	if q.first > q.last {
		return nil, errQueueEmpty
	}

	q.first++

	fn := filepath.Join(q.dir, fmt.Sprintf("%d", q.first))
	out, err := ioutil.ReadFile(fn)
	if err != nil {
		return nil, err
	}

	if err := os.Remove(fn); err != nil {
		return nil, err
	}

	return out, nil
}

func (q *queue) enqueue(b []byte) error {
	q.mutex.Lock()
	defer q.mutex.Unlock()

	q.last++

	fn := filepath.Join(q.dir, fmt.Sprintf("%d", q.last))
	if err := ioutil.WriteFile(fn, b, 0600); err != nil {
		return err
	}

	return nil
}

func main() {
	if len(os.Args) != 2 {
		panic("provide a directory name")
	}

	dir := os.Args[1]
	os.MkdirAll(dir, 0700)

	q, err := newQueue(dir)
	if err != nil {
		panic(err)
	}

	i := q.last + 1

	go func() {
		for {
			b, err := q.dequeue()
			if err != nil {
				time.Sleep(10 * time.Millisecond)
				continue
			}

			fmt.Println(string(b))
		}
	}()

	for {
		time.Sleep(10 * time.Millisecond) // throttle it to avoid filling disk too fast
		if err := q.enqueue([]byte(fmt.Sprintf("%d", i))); err != nil {
			panic(err)
		}

		i++
	}
}
```

So, when you start this queue, stop it, and start it again, it will resume where it left off. Try it! Run it like so:

```bash
go run main.go /tmp/foo
```

And press `Control+C` to exit it. `ls /tmp/foo`. Notice how it's full of files? Those are your queue elements; each one will contain its value as the content. Working as intended!

If you want to see it repeat itself from it's last state:

```bash
go run main.go /tmp/foo | head -10
```

Run that a few times. It will yield the first ten items of the queue.

When you're done, just `rm -r` the directory.

### So you said this wasn't kosher. What gives?

On POSIX-compliant systems (pretty much everyone), there's a thing called `EINTR`, it's a constant that's short for "Interrupted System Call". While Golang handles this very elegantly in spots, what it _means_ is that your _transactions_ (the writes to the filesystem) can be interrupted, so they have to be retried. This most commonly occurs when a signal is fired; like the "interrupt" (`SIGINT`) signal you sent when you last pressed `Control+C`, as well as the `head -1` signalling the exit by way of `SIGPIPE`, another signal used to determine to a process writing to a pipe that its reader has died.

Again, Golang will handle this well and terminate early or persist the write regardless, but we're still _losing data_. If you're watching carefully, that number jumps a few points when you do either thing from time to time -- that's de-sync from the queue's internal state and the filesystem.

You can read more about [EINTR here](https://unix.stackexchange.com/a/509644). `man 7 signal` for documentation on signals.

The solution here is not especially complicated but also deceptively delicate: a signal handler, plus some more detailed file management around reading and writing would be in order to correct some of these edge cases. DB safety outside of the program is a non-starter.

The problem here is not necessarily the performance or overhead of the solution; but the effort required to maintain it and verify it.

## So what's next? More databases?

Yes, let's try a SQLite database next. SQLite is nice because we can both model it entirely in memory or on disk, allowing for some more interesting deployment strategies in complicated scenarios. It's also made to run alongside our program, ensuring that signal handling is simple (just close the db).

SQL is its own beast though, and comes with its own, unique woes.

Let's look at what that approach might look like. Here is a basic queue that just fills a database and retrieves it in lockstep; we can lock the transaction for now with a mutex (more on this later, though) and just gate it that way, using the database as backing storage leveraging very few of SQL's concurrency management tools.

We'll be using [mattn/go-sqlite3](https://github.com/mattn/go-sqlite3) to manage our database, although you may want to consider using a higher level component such as [GORM](https://gorm.io) for a larger application.

```go
package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"sync"

	_ "github.com/mattn/go-sqlite3"
)

var errQueueEmpty = errors.New("queue is empty")

type queue struct {
	db    *sql.DB
	mutex sync.Mutex
}

func newQueue(dbFile string) (*queue, error) {
	db, err := sql.Open("sqlite3", fmt.Sprintf("file:%s", dbFile))
	if err != nil {
		return nil, err
	}

	// not checking the error so we can run it multiple times
	db.Exec(`
create table queue (
	idx integer primary key autoincrement,
	value unsigned integer not null
)
	`)

	return &queue{db: db}, nil
}

func (q *queue) dequeue() (uint64, error) {
	q.mutex.Lock()
	defer q.mutex.Unlock()

	tx, err := q.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var (
		idx int64
		u   uint64
	)

	if err := tx.QueryRow("select idx, value from queue order by idx limit 1").Scan(&idx, &u); err != nil {
		return 0, err
	}

	res, err := tx.Exec("delete from queue where idx=?", idx)
	if err != nil {
		return 0, err
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}

	if rows == 0 {
		return 0, errQueueEmpty
	}

	return u, tx.Commit()
}

func (q *queue) enqueue(x uint64) error {
	q.mutex.Lock()
	defer q.mutex.Unlock()

	tx, err := q.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec("insert into queue (value) values (?)", x); err != nil {
		return err
	}

	return tx.Commit()
}

func main() {
	if len(os.Args) != 2 {
		panic("provide a database filename")
	}

	q, err := newQueue(os.Args[1])
	if err != nil {
		panic(err)
	}

	go func() {
		for {
			x, err := q.dequeue()
			if err != nil {
				continue
			}

			fmt.Println(fmt.Sprintf("%d", x))
		}
	}()

	i := uint64(0)

	for {
		if err := q.enqueue(i); err != nil {
			panic(err)
		}

		i++
	}
}
```

You can run this with the following:

```
go run main.go foo.db
```

Run it multiple times to see the restart. It should never be off.

### So, what's wrong with it?

So, there are a number of issues with this approach. Nothing is inherenly _wrong_ with this approach, though, unlike the filesystem example. You can use this, if all you want to queue are unsigned integers.

#### SQL is a lot of overhead

SQL has to be parsed, the syntax is optimized and then in almost every database, there is a second layer of optimization that works against indexes and other structures within the database itself just to make a query. While definitely having its place it's a lot of overhead for us.

#### SQL transactions have weird semantics

They're also sluggish and tend to vary between database platforms.

AKA, this is why we're using a mutex. I have never personally found SQL's transactional systems to be anything but "clear as mud", especially when working with more stringent levels of isolation. In this case, a simple mutex mitigates the kind of contention in the database that transactions typically fail at, miserably.

Which brings me to my last point...

#### It's slow

It's just slow. It does the job and if you were on a phone or something and were limited on tooling, sure. Maybe. But there are better options for this problem.

# A wild BoltDB appears

[BoltDB](https://github.com/boltdb/bolt) is a key/value storage engine for golang that is in the spirit of [LMDB](http://www.lmdb.tech/doc/), another popular key/value store developed in C.

We'll be using the [bbolt](https://github.com/etcd-io/bbolt) variant, for our purposes, since it seems to be better maintained.

```go
package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"

	"go.etcd.io/bbolt"
)

var errQueueEmpty = errors.New("queue is empty")

type queue struct {
	db *bbolt.DB
}

func newQueue(dbFile string) (*queue, error) {
	db, err := bbolt.Open(dbFile, 0600, nil)
	if err != nil {
		return nil, err
	}

	return &queue{db: db}, db.Update(func(tx *bbolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte("queue"))
		return err
	})
}

func (q *queue) pop() (uint64, uint64, error) {
	var idx, u uint64

	err := q.db.Update(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte("queue"))
		cur := bucket.Cursor()
		key, value := cur.First()
		if key == nil {
			return errQueueEmpty
		}

		idx = binary.BigEndian.Uint64(key)
		u = binary.BigEndian.Uint64(value)
		return bucket.Delete(key)
	})

	return idx, u, err
}

func (q *queue) enqueue(x uint64) error {
	return q.db.Update(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte("queue"))

		seq, err := bucket.NextSequence()
		if err != nil {
			return err
		}

		key := make([]byte, 8)
		value := make([]byte, 8)

		binary.BigEndian.PutUint64(key, seq)
		binary.BigEndian.PutUint64(value, x)
		return bucket.Put(key, value)
	})
}

func main() {
	if len(os.Args) != 2 {
		panic("provide a database filename")
	}

	q, err := newQueue(os.Args[1])
	if err != nil {
		panic(err)
	}

	go func() {
		for {
			idx, x, err := q.pop()
			if err != nil {
				continue
			}

			fmt.Println(fmt.Sprintf("%d: %d", idx, x))
		}
	}()

	i := uint64(0)

	for {
		if err := q.enqueue(i); err != nil {
			panic(err)
		}

		i++
	}
}
```

You run this one just like the last one:

```bash
go run main.go bar.db # not the same db! ;)
```

And you can restart it, pipe it to `head` and so on. It outputs two numbers this time, one corresponding to the index, and another that indicates from 0 the items entered during that process run; this number will reset as you restart the process, but depending on how fast you drain you will not see the repeats immediately. The index will not repeat.

Because the signal handler interrupts the `fmt.Println`, most of the time we do not see the last value cleared; so there will be a 1 unit gap.

## How does it work?

The `NextSequence()` calls yield an integer which is then packed into a 8-byte array, which is how large a `uint64` is. It is this stored along with your own value in similar fashion, also a `uint64`. For return, it simply pulls the first item the cursor yields and deletes it.

BoltDB's cursors are nice in the fact that they always return the keys in sorted byte order, so this works without ever consulting the tail at all, or worrying about sorting. The db is happily persisted and all is good in the world; if you're feeling paranoid, a signal handler will finish the job here.

## Advantages

There are a lot of advantages to this pattern and it's one I think I'm fairly comfortable using and talking about, so here are a lot of advantages over the others:

### Locking is a solved problem

The `Update()` calls automatically enter a transaction when the inner function is called; if an error is returned, the transaction is automatically rolled back. You may notice I opted for a similar pattern with the SQL code, just doing it by hand. The `Update()` call here is done under database lock so no writers can interact with the database at all until the transaction completes. This is functionally a mutex for us.

### It's fast

Try it! Compare it to the SQL version. The bbolt version does much much less despite being a similar amount of code. It also creates smaller data structures that need less work to iterate. This is a better solution on performance overall.

### It's pretty damn easy

The code above is not that complicated, contains no real "gotchas", and isn't that hard to read (at least, I don't think). The bbolt solution wins on the maintainability front, as well. If you need multiple queues in a single database, use multiple buckets. You can even relate non-queue k/v data to the queue in a separate bucket and handle that all under `View()` or `Update()` calls safely. You just need to understand how bbolt manages its keys and the relationship between keys and cursors.

# Thanks for Reading

I hope you've enjoyed this content! Come back for more, eventually, when I get the will to write!
