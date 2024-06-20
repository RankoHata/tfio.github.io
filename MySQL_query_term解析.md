# Query Term

> [sql\query_term.h](https://github.com/mysql/mysql-server/blob/8.0/sql/query_term.h)

```cpp
Example: ((SELECT * FROM t1 UNION SELECT * FROM t2 UNION ALL SELECT * FROM t3
           ORDER BY a LIMIT 5) INTERSECT
          (((SELECT * FROM t3 ORDER BY a LIMIT 4) ) EXCEPT SELECT * FROM t4)
          ORDER BY a LIMIT 4) ORDER BY -a LIMIT 3;

->
            m_query_term   +------------------+     slave(s)
            +--------------|-Query_expression |------------------+
            |              +------------------+                  |
            V        post_                                       |
+-------------------+processing_ +----------------------+        |
| Query_term_unary  |block()     |Query_block           |        |
|                   |----------->|order by -(`a) limit 3|        |
+-------------------+            +----------------------+        |
 |m_children                                                     |
 | +-----------------------+   +----------------------+          |
 | |Query_term_intersect   |   |Query_block           |          |
 +>|last distinct index: 1 |-->|order by `a` limit 4  |          |
   +-----------------------+   +----------------------+          |
    |m_children                                                  |
    |  +-----------------------+   +----------------------+      |
    |  |Query_term_union       |   |Query_block           |      |
    +->|last distinct index: 1 |-->|order by `a`  limit 5 |      |
    |  +-----------------------+   +----------------------+      |
    |    |m_children                                             |
    |    |   +------------+        SELECT * FROM t1             /
    |    +-->|Query_block |  <---------------------------------+
    |    |   +------------+  ----------------------------------+ next
    |    |                                                      \
    |    |   +------------+        SELECT * FROM t2             /
    |    +-->|Query_block |  <---------------------------------+
    |    |   +------------+  ----------------------------------+ next
    |    |                                                      \
    |    |   +------------+        SELECT * FROM t3             /
    |    +-->|Query_block |  <---------------------------------+
    |        +------------+  ----------------------------------+ next
    |                                                           \
    |  +-----------------------+  +------------+                 |
    |  |Query_term_except      |->|Query_block |                 |
    +->|last distinct index: 1 |  +------------+                 |
       +-----------------------+                                 |
         |m_children                                             |
         |   +----------------------+                            |
         |   |Query_block           |      SELECT * FROM t3      /
         +-->|order by `a`  limit 4 |  <------------------------+
         |   +----------------------+  -------------------------+ next
         |                                                       \
         |   +------------+                SELECT * FROM t4      |
         +-->|Query_block | <------------------------------------+
             +------------+
```