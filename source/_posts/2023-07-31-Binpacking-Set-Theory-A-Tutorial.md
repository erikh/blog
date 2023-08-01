---
title: "Binpacking & Set Theory: A Tutorial"
date: 2023-07-31 22:12:09
tags:
    - Programming
---

One thing a good scheduler must do is "binpack", which is the art of finding the right spot for your special program to run in a group of otherwise able computers. Computers have limited resources, and staying within those limits is key to having a good multi-tenant experience. Binpacking is named as such in relationship to the concept of several bins of pears at a pear farm in a line, collecting pears from the trees. You will fill the bins at different rates, so knowing both when the bins are full and how to divert the resources to available bins is a very important part of scheduling.

Binpacking is fundamentally a set theory problem, which I will demonstrate with basic binary operations. This is a simplification of the problem, but we'll get into more advanced scenarios in a bit.

First off, the goal is to turn all these `0`s into `1`s:

```
0100000100001000
```

Until then, the number really isn't saturated, now is it? So let's do a binary "exclusive OR" operation with this other number! This will give us the result we want:

```
1011111011110111
```

Since "exclusive OR" gives us a `1` if either is true, but not both, we get the result we want without colliding.

```
1111111111111111
```

And this number cannot be amended now without turning a `1` back into a `0`. This is the basis of how a scheduler works within a single node, but also amongst the whole cluster.

Think of each one of those `1`s as a taken CPU, and every `0` as a free one. Now, this is a single vector, which we can combine with other vectors such as memory usage or even much more subtle metrics like CPU pressure to determine a suitable host to stuff our container or VM onto.

A good way to express set theory with an arbitrary number of parameters is SQL, since it is more or less designed to handle this problem in all sorts of nefarious ways. Most of this tutorial will be based in the SQL language, so if you want to take it to your favorite general purpose language and use these ideas that way, great! It's probably gonna handle SQL fine. Also keep in mind that none of these techniques are expressly limited to SQL, they're just easier to model in a SQL language. A RDBMS generally has other drawbacks that many schedulers, especially big ones made by Google are not willing to tolerate. As with any large undertaking of importance, it's critical to weigh your advantages and your disadvantages to the given situation.

All SQL is targeted at PostgreSQL idioms, but should be trivial to port to e.g. SQLite or MySQL.

Let's start with a good schema for our database:

```sql
-- list of the nodes. this is our physical (as far as we're concerned at least)
-- representation of computing resources.
CREATE TABLE nodes (
    id serial primary key,
    ip varchar not null,
    total_cpus int not null, -- this is usually measured in vCPU which is 0.5 CPUs, usually a single CPU thread
    total_mem int not null,  -- probably in gigabytes but depends on the scenario
    total_disk int not null  -- disk is usually much more complicated than this
);

-- this how you create an enum in postgres
CREATE TYPE metric AS ENUM('cpu', 'memory', 'disk');

-- each entry indicates a block of that metric in use
create table nodes_stats (
    node_id int not null,
    metric metric not null
);
```

To reiterate what the comments say, we keep one table, called `nodes`, which is a representation of our physical limits for each instance we manage. We then store a metric for each unit in use.

To enter a new node, we simply insert it with its fixed stats:

```sql
INSERT INTO nodes (ip, total_cpus, total_mem, total_disk) values ('127.0.0.1', 24, 64, 100) returning id;
```

To enter a new usage, we simply insert into the `nodes_stats` table:

```sql
INSERT INTO nodes_stats (node_id, metric) values (1, 'cpu');
```

To query nodes that are available for use, we have to get a little more creative. What we do here is count the number of metrics for a given vector that are in use, then we subtract that number from the total available and see if it meets our requirement. This is very similar to what the exclusive OR does above semantically, but just with larger pieces of data.

Please note in this query that `target_cpu`, `target_mem` and `target_disk` are all placeholders and depend on what kind of data you wish to require. It's also expected that you would do this with a transaction that also inserted the used data, ensuring basic atomicity.

```sql
SELECT nodes.id, cpu.metric, mem.metric, disk.metric
FROM nodes
LEFT OUTER JOIN (SELECT nodes.id AS id, count(metric) as metric
     FROM nodes_stats
     INNER JOIN nodes ON nodes.id = node_id
     WHERE metric = 'cpu'
     GROUP by nodes.id, nodes.total_cpus
     HAVING(nodes.total_cpus - count(metric) < nodes.total_cpus - target_cpu)
    ) as cpu ON nodes.id = cpu.id
LEFT OUTER JOIN (SELECT nodes.id AS id, count(metric) as metric
     FROM nodes_stats
     INNER JOIN nodes ON nodes.id = node_id
     WHERE metric = 'memory'
     GROUP by nodes.id, nodes.total_mem
     HAVING(nodes.total_mem - count(metric) < nodes.total_mem - target_mem)
    ) as mem ON nodes.id = mem.id
LEFT OUTER JOIN (SELECT nodes.id AS id, count(metric) as metric
     FROM nodes_stats
     INNER JOIN nodes ON nodes.id = node_id
     WHERE metric = 'disk'
     GROUP by nodes.id, nodes.total_disk
     HAVING(nodes.total_disk - count(metric) < nodes.total_disk - target_disk)
    ) as disk ON nodes.id = disk.id
WHERE (
  cpu.metric IS NOT NULL AND
  mem.metric IS NOT NULL AND
  disk.metric IS NOT NULL
) OR (
  cpu.metric IS NULL AND
  mem.metric IS NULL AND
  disk.metric IS NULL
)
LIMIT 1;
```

This query will select a free node every time, provided you're inserting your metrics once you find something suitable in an atomic way.

Anyway, there you have it! Hope you enjoyed this, it was fun to put it together.
