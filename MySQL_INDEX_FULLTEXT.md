# 关于MySQL数据fulltext索引的一些梳理

## 简单查询对应的执行计划与源码简单分析记录

### 表结构

```sql
mysql> show create table tmp_y;
+-------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                                                                                      |
+-------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| tmp_y | CREATE TABLE `tmp_y` (
  `k` int(11) NOT NULL AUTO_INCREMENT,
  `content` text,
  PRIMARY KEY (`k`),
  FULLTEXT KEY `idx` (`content`) /*!50100 WITH PARSER `ngram` */ 
) ENGINE=InnoDB AUTO_INCREMENT=290795 DEFAULT CHARSET=utf8 |
+-------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

### PLAN

#### 仅作为where条件

```sql
mysql> explain select * from tmp_y where match(content) against('小玲XX');
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-------------------------------+
| id | select_type | table | partitions | type     | possible_keys | key  | key_len | ref   | rows | filtered | Extra                         |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-------------------------------+
|  1 | SIMPLE      | tmp_y | NULL       | fulltext | idx           | idx  | 0       | const |    1 |   100.00 | Using where; Ft_hints: sorted |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-------------------------------+
1 row in set, 1 warning (4.54 sec)

mysql> explain select * from tmp_y where match(content) against('小玲XX') limit 5;
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
| id | select_type | table | partitions | type     | possible_keys | key  | key_len | ref   | rows | filtered | Extra                                    |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
|  1 | SIMPLE      | tmp_y | NULL       | fulltext | idx           | idx  | 0       | const |    1 |   100.00 | Using where; Ft_hints: sorted, limit = 5 |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
1 row in set, 1 warning (4.53 sec)
```

设置3断点

```shell
Item_func_match::set_hints
fts_query
ha_innobase::ft_read
```

当match函数仅在where内，没orderby的时候，Ft_hints会设置sorted
FT_SORTED 这个flag其实对 innodb 没有用，有效的场景应该是 myisam 引擎(innodb引擎最终调ft_read都会排的)

```cpp
Breakpoint 1, Item_func_match::set_hints (this=0x7fe64cfa5800, join=0x7fe64cfa6620, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
8184	  assert(!master);
(gdb) bt
#0  Item_func_match::set_hints (this=0x7fe64cfa5800, join=0x7fe64cfa6620, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
#1  0x0000000001519da5 in JOIN::optimize_fts_query (this=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_optimizer.cc:10819
#2  0x0000000001500723 in JOIN::optimize (this=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#3  0x0000000001577fa6 in st_select_lex::optimize (this=0x7fe64cfa4ad0, thd=0x7fe64c012500)
    at /data/Code/mysql-server/sql/sql_select.cc:1016


Breakpoint 3, fts_query (trx=0x7fe6d5f678c0, index=0x7fe64cfb4990, flags=2, query_str=0x7fe64cfa5738 "小玲XX", query_len=8, 
    result=0x7fe6d419a978, limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
3974		dberr_t		error = DB_SUCCESS;
(gdb) bt
#0  fts_query (trx=0x7fe6d5f678c0, index=0x7fe64cfb4990, flags=2, query_str=0x7fe64cfa5738 "小玲XX", query_len=8, result=0x7fe6d419a978, 
    limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
#1  0x00000000018bf0aa in ha_innobase::ft_init_ext (this=0x7fe64cfa6e90, flags=2, keynr=1, key=0x7fe64cfa5758)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9511
#2  0x00000000018bf278 in ha_innobase::ft_init_ext_with_hints (this=0x7fe64cfa6e90, keynr=1, key=0x7fe64cfa5758, hints=0x7fe64cfa6600)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9551
#3  0x0000000000fbb0f0 in Item_func_match::init_search (this=0x7fe64cfa5800, thd=0x7fe64c012500)
    at /data/Code/mysql-server/sql/item_func.cc:7835
#4  0x00000000014ae57a in init_ftfuncs (thd=0x7fe64c012500, select_lex=0x7fe64cfa4ad0) at /data/Code/mysql-server/sql/sql_base.cc:10116
#5  0x0000000001519e29 in JOIN::optimize_fts_query (this=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_optimizer.cc:10831
#6  0x0000000001500723 in JOIN::optimize (this=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#7  0x0000000001577fa6 in st_select_lex::optimize (this=0x7fe64cfa4ad0, thd=0x7fe64c012500)
    at /data/Code/mysql-server/sql/sql_select.cc:1016

(gdb) p	limit
$4 = 18446744073709551615
(gdb) p	flags
$5 = 2

注意此时，flags已经是 FT_SORTED, 但是limit并没有值，即使SQL语句中存在limit
根据代码，limit只有在上层判定为 NO_RANKING 才会将真正的limit值带到查询处，当前不知道怎么触发


Breakpoint 4, ha_innobase::ft_read (this=0x7fe64cfa6e90, buf=0x7fe64cfa7188 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
9607		TrxInInnoDB	trx_in_innodb(m_prebuilt->trx);
(gdb) bt
#0  ha_innobase::ft_read (this=0x7fe64cfa6e90, buf=0x7fe64cfa7188 "\376\005p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
#1  0x00000000014e2d66 in join_ft_read_next (info=0x7fe64cf9de00) at /data/Code/mysql-server/sql/sql_executor.cc:2738
#2  0x00000000014df515 in sub_select (join=0x7fe64cfa6620, qep_tab=0x7fe64cf9ddb0, end_of_records=false)
    at /data/Code/mysql-server/sql/sql_executor.cc:1287
#3  0x00000000014dee92 in do_select (join=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_executor.cc:957
#4  0x00000000014dcdf9 in JOIN::exec (this=0x7fe64cfa6620) at /data/Code/mysql-server/sql/sql_executor.cc:206

对于 ft_read 断点，limit几就会走几次，在 sub_select 函数内会进行循环控制，达到数目之后即会跳出。
```

#### 作为 order by 条件

```sql
mysql> explain select * from tmp_y order by match(content) against('小玲XX') asc limit 5;
+----+-------------+-------+------------+------+---------------+------+---------+------+--------+----------+----------------+
| id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra          |
+----+-------------+-------+------------+------+---------------+------+---------+------+--------+----------+----------------+
|  1 | SIMPLE      | tmp_y | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 130536 |   100.00 | Using filesort |
+----+-------------+-------+------------+------+---------------+------+---------+------+--------+----------+----------------+
1 row in set, 1 warning (3.21 sec)

mysql> explain select * from tmp_y order by match(content) against('小玲XX') desc limit 5;
+----+-------------+-------+------------+----------+---------------+------+---------+------+--------+----------+-----------------------------+
| id | select_type | table | partitions | type     | possible_keys | key  | key_len | ref  | rows   | filtered | Extra                       |
+----+-------------+-------+------------+----------+---------------+------+---------+------+--------+----------+-----------------------------+
|  1 | SIMPLE      | tmp_y | NULL       | fulltext | NULL          | idx  | 4       | NULL | 130536 |   100.00 | Ft_hints: sorted, limit = 5 |
+----+-------------+-------+------------+----------+---------------+------+---------+------+--------+----------+-----------------------------+
1 row in set, 1 warning (4.83 sec)
```

设置断点

Item_func_match::set_hints
fts_query
ha_innobase::ft_read
innobase_fts_retrieve_docid
innobase_fts_find_ranking

对于降序，我们可以走全文索引，但是对于升序，执行计划中不走索引，但实际上 fts_query 也会被调用，因为还是需要使用相关数据做判断的.

降序：limit次 ft_read
升序：row_num次 rankTree搜索

##### DESC

```cpp
Breakpoint 2, fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065a8 "小玲XX", query_len=8, 
    result=0x7f5d0c08c978, limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
3974		dberr_t		error = DB_SUCCESS;
(gdb) bt
#0  fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065a8 "小玲XX", query_len=8, result=0x7f5d0c08c978, 
    limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
#1  0x00000000018bf0aa in ha_innobase::ft_init_ext (this=0x7f5c9400ff10, flags=0, keynr=1, key=0x7f5c940065c8)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9511
#2  0x00000000018bf278 in ha_innobase::ft_init_ext_with_hints (this=0x7f5c9400ff10, keynr=1, key=0x7f5c940065c8, hints=0x7f5c940074b8)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9551
#3  0x0000000000fbb0f0 in Item_func_match::init_search (this=0x7f5c94006670, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/item_func.cc:7835
#4  0x00000000014ae57a in init_ftfuncs (thd=0x7f5c94000b70, select_lex=0x7f5c94005940) at /data/Code/mysql-server/sql/sql_base.cc:10116
#5  0x0000000001519e29 in JOIN::optimize_fts_query (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:10831
#6  0x0000000001500723 in JOIN::optimize (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#7  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005940, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#8  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c940070f8, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#9  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006a18)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#10 0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#11 0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#12 0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
---Type <return> to continue, or q <return> to quit---q
 at /data/Code/mysql-server/sql/sQuit
(gdb) c
Continuing.

Breakpoint 1, Item_func_match::set_hints (this=0x7f5c94006670, join=0x7f5c9493d280, ft_flag=2, ft_limit=5, no_cond=true)
    at /data/Code/mysql-server/sql/item_func.cc:8184
8184	  assert(!master);
(gdb) bt
#0  Item_func_match::set_hints (this=0x7f5c94006670, join=0x7f5c9493d280, ft_flag=2, ft_limit=5, no_cond=true)
    at /data/Code/mysql-server/sql/item_func.cc:8184
#1  0x00000000015043dd in test_if_skip_sort_order (tab=0x7f5c94007500, order=0x7f5c940067f0, select_limit=5, no_changes=false, 
    map=0x7f5c9400f5e8, clause_type=0x1f9679a "ORDER BY") at /data/Code/mysql-server/sql/sql_optimizer.cc:1947
#2  0x0000000001503471 in JOIN::test_skip_sort (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:1375
#3  0x0000000001500f0f in JOIN::optimize (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:665
#4  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005940, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#5  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c940070f8, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#6  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006a18)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#7  0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#8  0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#9  0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#10 0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#11 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#12 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
---Type <return> to continue, or q <return> to quit---q
Quit
(gdb) c
Continuing.

Breakpoint 5, ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
9607		TrxInInnoDB	trx_in_innodb(m_prebuilt->trx);
(gdb) bt
#0  ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
#1  0x00000000014e2cf8 in join_ft_read_first (tab=0x7f5c9493d730) at /data/Code/mysql-server/sql/sql_executor.cc:2729
#2  0x00000000014df4ff in sub_select (join=0x7f5c9493d280, qep_tab=0x7f5c9493d730, end_of_records=false)
    at /data/Code/mysql-server/sql/sql_executor.cc:1284
#3  0x00000000014dee92 in do_select (join=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_executor.cc:957
#4  0x00000000014dcdf9 in JOIN::exec (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_executor.cc:206
#5  0x000000000157677b in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c940070f8, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:191
#6  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006a18)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#7  0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#8  0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#9  0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#10 0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#11 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#12 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
#13 0x00007f5d18430ea5 in start_thread () from /lib64/libpthread.so.0
---Type <return> to continue, or q <return> to quit---q
Quit
(gdb) 
```

总结：
1. fts_query // 查询数据
2. set_hints // 设置相关flag（虽然没什么用）
3. ft_read // 完成limit次查询

##### ASC

```cpp
Breakpoint 2, fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065a8 "小玲XX", query_len=8, 
    result=0x7f5d0c08c978, limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
3974		dberr_t		error = DB_SUCCESS;
(gdb) bt
#0  fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065a8 "小玲XX", query_len=8, result=0x7f5d0c08c978, 
    limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
#1  0x00000000018bf0aa in ha_innobase::ft_init_ext (this=0x7f5c9400ff10, flags=0, keynr=1, key=0x7f5c940065c8)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9511
#2  0x00000000018bf278 in ha_innobase::ft_init_ext_with_hints (this=0x7f5c9400ff10, keynr=1, key=0x7f5c940065c8, hints=0x7f5c940074b8)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9551
#3  0x0000000000fbb0f0 in Item_func_match::init_search (this=0x7f5c94006670, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/item_func.cc:7835
#4  0x00000000014ae57a in init_ftfuncs (thd=0x7f5c94000b70, select_lex=0x7f5c94005940) at /data/Code/mysql-server/sql/sql_base.cc:10116
#5  0x0000000001519e29 in JOIN::optimize_fts_query (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:10831
#6  0x0000000001500723 in JOIN::optimize (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#7  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005940, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#8  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c940070f8, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#9  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006a18)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#10 0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#11 0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#12 0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
---Type <return> to continue, or q <return> to quit---q
 at /data/Code/mysql-server/sql/sQuit
(gdb) c
Continuing.

Breakpoint 6, innobase_fts_find_ranking (fts_hdl=0x7f5c94dbc4a0, record=0x7f5c94010208 "\376\374o", len=0)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:18999
18999		ft_prebuilt = reinterpret_cast<NEW_FT_INFO*>(fts_hdl)->ft_prebuilt;
(gdb) bt
#0  innobase_fts_find_ranking (fts_hdl=0x7f5c94dbc4a0, record=0x7f5c94010208 "\376\374o", len=0)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:18999
#1  0x0000000000fbc153 in Item_func_match::val_real (this=0x7f5c94006670) at /data/Code/mysql-server/sql/item_func.cc:8153
#2  0x0000000000efdcf3 in Item::val_result (this=0x7f5c94006670) at /data/Code/mysql-server/sql/item.h:1599
#3  0x0000000000f0421a in Sort_param::make_sortkey (this=0x7f5d0c08cad0, to=0x7f5c94dbbf70 "0trx.cc", ref_pos=0x7f5c94010588 "\374o")
    at /data/Code/mysql-server/sql/filesort.cc:1464
#4  0x0000000000f078fb in Bounded_queue<unsigned char*, unsigned char*, Sort_param, (anonymous namespace)::Mem_compare>::push (
    this=0x7f5d0c08c990, element=0x7f5c94010588 "\374o") at /data/Code/mysql-server/sql/bounded_queue.h:115
#5  0x0000000000f02f26 in find_all_keys (param=0x7f5d0c08cad0, qep_tab=0x7f5c9493d730, fs_info=0x7f5d0c08ca50, chunk_file=0x7f5d0c08ccc0, 
    tempfile=0x7f5d0c08cb60, pq=0x7f5d0c08c990, found_rows=0x7f5d0c08cfb8) at /data/Code/mysql-server/sql/filesort.cc:1016
#6  0x0000000000f013fd in filesort (thd=0x7f5c94000b70, filesort=0x7f5c9493da20, sort_positions=false, examined_rows=0x7f5d0c08cfc0, 
    found_rows=0x7f5d0c08cfb8, returned_rows=0x7f5d0c08cfb0) at /data/Code/mysql-server/sql/filesort.cc:430
#7  0x00000000014e5648 in create_sort_index (thd=0x7f5c94000b70, join=0x7f5c9493d280, tab=0x7f5c9493d730)
    at /data/Code/mysql-server/sql/sql_executor.cc:3712
#8  0x00000000014e2852 in QEP_TAB::sort_table (this=0x7f5c9493d730) at /data/Code/mysql-server/sql/sql_executor.cc:2625
#9  0x00000000014e2246 in join_init_read_record (tab=0x7f5c9493d730) at /data/Code/mysql-server/sql/sql_executor.cc:2491
#10 0x00000000014df4ff in sub_select (join=0x7f5c9493d280, qep_tab=0x7f5c9493d730, end_of_records=false)
    at /data/Code/mysql-server/sql/sql_executor.cc:1284
#11 0x00000000014dee92 in do_select (join=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_executor.cc:957
#12 0x00000000014dcdf9 in JOIN::exec (this=0x7f5c9493d280) at /data/Code/mysql-server/sql/sql_executor.cc:206
---Type <return> to continue, or q <return> to quit---q
Quit
(gdb) n
19000		result = reinterpret_cast<NEW_FT_INFO*>(fts_hdl)->ft_result;
(gdb) n
19004		return(fts_retrieve_ranking(result, ft_prebuilt->fts_doc_id));
(gdb) p ft_prebuilt->fts_doc_id
$14 = 24581
(gdb) c
Continuing.

Breakpoint 6, innobase_fts_find_ranking (fts_hdl=0x7f5c94dbc4a0, record=0x7f5c94010208 "\376\375o", len=0)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:18999
18999		ft_prebuilt = reinterpret_cast<NEW_FT_INFO*>(fts_hdl)->ft_prebuilt;
(gdb) n
19000		result = reinterpret_cast<NEW_FT_INFO*>(fts_hdl)->ft_result;
(gdb) n
19004		return(fts_retrieve_ranking(result, ft_prebuilt->fts_doc_id));
(gdb) p ft_prebuilt->fts_doc_id
$15 = 24582
(gdb) 
```

总结：
1. fts_query // 查询数据
2. innobase_fts_find_ranking // 查询当前行对应的rank分数，这个有多少行执行多少次,这个就是使用当前的doc_id去rbTree里面查，不存在肯定是0，存在就可以得到得分

#### where + orderby 条件

```sql
mysql> explain select * from tmp_y where match(content) against('小玲XX') order by match(content) against('小玲XX') desc limit 5;
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
| id | select_type | table | partitions | type     | possible_keys | key  | key_len | ref   | rows | filtered | Extra                                    |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
|  1 | SIMPLE      | tmp_y | NULL       | fulltext | idx           | idx  | 0       | const |    1 |   100.00 | Using where; Ft_hints: sorted, limit = 5 |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+------------------------------------------+
1 row in set, 1 warning (6.07 sec)

mysql> explain select * from tmp_y where match(content) against('小玲XX') order by match(content) against('小玲XX') asc limit 5;
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-----------------------------+
| id | select_type | table | partitions | type     | possible_keys | key  | key_len | ref   | rows | filtered | Extra                       |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-----------------------------+
|  1 | SIMPLE      | tmp_y | NULL       | fulltext | idx           | idx  | 0       | const |    1 |   100.00 | Using where; Using filesort |
+----+-------------+-------+------------+----------+---------------+------+---------+-------+------+----------+-----------------------------+
1 row in set, 1 warning (3.16 sec)

```

设置断点

Item_func_match::set_hints
fts_query
ha_innobase::ft_read
innobase_fts_retrieve_docid
innobase_fts_find_ranking

对于where + 升序 + limit，理论上是等价于 where无limit + 内存排序 (row_num次 ft_read)
对于where + 降序 + limit，理论上是等价于 where有limit + 内存排序 (limit次 ft_read)

##### DESC

```cpp
Breakpoint 1, Item_func_match::set_hints (this=0x7f5c940066c0, join=0x7f5c9493d4e0, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
8184	  assert(!master);
(gdb) bt
#0  Item_func_match::set_hints (this=0x7f5c940066c0, join=0x7f5c9493d4e0, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
#1  0x0000000001519da5 in JOIN::optimize_fts_query (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:10819
#2  0x0000000001500723 in JOIN::optimize (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#3  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005990, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#4  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#5  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#6  0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#7  0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#8  0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#9  0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#10 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#11 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
#12 0x00007f5d18430ea5 in start_thread () from /lib64/libpthread.so.0
#13 0x00007f5d16c2196d in clone () from /lib64/libc.so.6
(gdb) c
Continuing.

Breakpoint 2, fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=2, query_str=0x7f5c940065f8 "小玲XX", query_len=8, 
    result=0x7f5d0c08c978, limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
3974		dberr_t		error = DB_SUCCESS;
(gdb) bt
#0  fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=2, query_str=0x7f5c940065f8 "小玲XX", query_len=8, result=0x7f5d0c08c978, 
    limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
#1  0x00000000018bf0aa in ha_innobase::ft_init_ext (this=0x7f5c9400ff10, flags=2, keynr=1, key=0x7f5c94006618)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9511
#2  0x00000000018bf278 in ha_innobase::ft_init_ext_with_hints (this=0x7f5c9400ff10, keynr=1, key=0x7f5c94006618, hints=0x7f5c940077e0)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9551
#3  0x0000000000fbb0f0 in Item_func_match::init_search (this=0x7f5c940066c0, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/item_func.cc:7835
#4  0x00000000014ae57a in init_ftfuncs (thd=0x7f5c94000b70, select_lex=0x7f5c94005990) at /data/Code/mysql-server/sql/sql_base.cc:10116
#5  0x0000000001519e29 in JOIN::optimize_fts_query (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:10831
#6  0x0000000001500723 in JOIN::optimize (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#7  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005990, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#8  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#9  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#10 0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#11 0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#12 0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
---Type <return> to continue, or q <return> to quit---
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#13 0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#14 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#15 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
#16 0x00007f5d18430ea5 in start_thread () from /lib64/libpthread.so.0
#17 0x00007f5d16c2196d in clone () from /lib64/libc.so.6
(gdb) c
Continuing.

Breakpoint 1, Item_func_match::set_hints (this=0x7f5c940066c0, join=0x7f5c9493d4e0, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
8184	  assert(!master);
(gdb) bt
#0  Item_func_match::set_hints (this=0x7f5c940066c0, join=0x7f5c9493d4e0, ft_flag=2, ft_limit=5, no_cond=false)
    at /data/Code/mysql-server/sql/item_func.cc:8184
#1  0x0000000001504271 in test_if_skip_sort_order (tab=0x7f5c9493d8b8, order=0x7f5c94006c10, select_limit=5, no_changes=false, 
    map=0x7f5c9400f5e8, clause_type=0x1f9679a "ORDER BY") at /data/Code/mysql-server/sql/sql_optimizer.cc:1921
#2  0x0000000001503471 in JOIN::test_skip_sort (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:1375
#3  0x0000000001500f0f in JOIN::optimize (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:665
#4  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005990, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#5  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#6  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#7  0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#8  0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#9  0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#10 0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#11 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#12 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
---Type <return> to continue, or q <return> to quit---q
Quit
(gdb) c
Continuing.

Breakpoint 5, ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
9607		TrxInInnoDB	trx_in_innodb(m_prebuilt->trx);
(gdb) bt
#0  ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
#1  0x00000000014e2cf8 in join_ft_read_first (tab=0x7f5c9493e5d0) at /data/Code/mysql-server/sql/sql_executor.cc:2729
#2  0x00000000014df4ff in sub_select (join=0x7f5c9493d4e0, qep_tab=0x7f5c9493e5d0, end_of_records=false)
    at /data/Code/mysql-server/sql/sql_executor.cc:1284
#3  0x00000000014dee92 in do_select (join=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_executor.cc:957
#4  0x00000000014dcdf9 in JOIN::exec (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_executor.cc:206
#5  0x000000000157677b in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:191
#6  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#7  0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#8  0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#9  0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
    at /data/Code/mysql-server/sql/sql_parse.cc:1492
#10 0x0000000001521868 in do_command (thd=0x7f5c94000b70) at /data/Code/mysql-server/sql/sql_parse.cc:1031
#11 0x00000000016551a4 in handle_connection (arg=0x3ab10b0)
    at /data/Code/mysql-server/sql/conn_handler/connection_handler_per_thread.cc:313
#12 0x0000000001ce5cbc in pfs_spawn_thread (arg=0x3adc560) at /data/Code/mysql-server/storage/perfschema/pfs.cc:2197
#13 0x00007f5d18430ea5 in start_thread () from /lib64/libpthread.so.0
---Type <return> to continue, or q <return> to quit---q
Quit
```

降序的情况下，ft_read会调用 limit 次

##### ASC

```cpp
Breakpoint 2, fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065f8 "小玲XX", query_len=8, 
    result=0x7f5d0c08c978, limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
3974		dberr_t		error = DB_SUCCESS;
(gdb) bt
#0  fts_query (trx=0x7f5d0ee588c0, index=0x39a6390, flags=0, query_str=0x7f5c940065f8 "小玲XX", query_len=8, result=0x7f5d0c08c978, 
    limit=18446744073709551615) at /data/Code/mysql-server/storage/innobase/fts/fts0que.cc:3974
#1  0x00000000018bf0aa in ha_innobase::ft_init_ext (this=0x7f5c9400ff10, flags=0, keynr=1, key=0x7f5c94006618)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9511
#2  0x00000000018bf278 in ha_innobase::ft_init_ext_with_hints (this=0x7f5c9400ff10, keynr=1, key=0x7f5c94006618, hints=0x7f5c940077e0)
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9551
#3  0x0000000000fbb0f0 in Item_func_match::init_search (this=0x7f5c940066c0, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/item_func.cc:7835
#4  0x00000000014ae57a in init_ftfuncs (thd=0x7f5c94000b70, select_lex=0x7f5c94005990) at /data/Code/mysql-server/sql/sql_base.cc:10116
#5  0x0000000001519e29 in JOIN::optimize_fts_query (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:10831
#6  0x0000000001500723 in JOIN::optimize (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_optimizer.cc:510
#7  0x0000000001577fa6 in st_select_lex::optimize (this=0x7f5c94005990, thd=0x7f5c94000b70)
    at /data/Code/mysql-server/sql/sql_select.cc:1016
#8  0x0000000001576703 in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:171
#9  0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#10 0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
#11 0x000000000152cf83 in mysql_parse (thd=0x7f5c94000b70, parser_state=0x7f5d0c08e550) at /data/Code/mysql-server/sql/sql_parse.cc:5584
#12 0x0000000001522936 in dispatch_command (thd=0x7f5c94000b70, com_data=0x7f5d0c08ecb0, command=COM_QUERY)
---Type <return> to continue, or q <return> to quit---q
 at /data/Code/mysql-server/sql/sQuit
(gdb) c
Continuing.

Breakpoint 5, ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
9607		TrxInInnoDB	trx_in_innodb(m_prebuilt->trx);
(gdb) bt
#0  ha_innobase::ft_read (this=0x7f5c9400ff10, buf=0x7f5c94010208 "\376\033p")
    at /data/Code/mysql-server/storage/innobase/handler/ha_innodb.cc:9607
#1  0x00000000017199ca in FT_SELECT::get_next (this=0x7f5c94dc2f90) at /data/Code/mysql-server/sql/opt_range.h:1031
#2  0x0000000000f02ca1 in find_all_keys (param=0x7f5d0c08cad0, qep_tab=0x7f5c9493e5d0, fs_info=0x7f5d0c08ca50, chunk_file=0x7f5d0c08ccc0, 
    tempfile=0x7f5d0c08cb60, pq=0x7f5d0c08c990, found_rows=0x7f5d0c08cfb8) at /data/Code/mysql-server/sql/filesort.cc:977
#3  0x0000000000f013fd in filesort (thd=0x7f5c94000b70, filesort=0x7f5c9493e8c0, sort_positions=false, examined_rows=0x7f5d0c08cfc0, 
    found_rows=0x7f5d0c08cfb8, returned_rows=0x7f5d0c08cfb0) at /data/Code/mysql-server/sql/filesort.cc:430
#4  0x00000000014e5648 in create_sort_index (thd=0x7f5c94000b70, join=0x7f5c9493d4e0, tab=0x7f5c9493e5d0)
    at /data/Code/mysql-server/sql/sql_executor.cc:3712
#5  0x00000000014e2852 in QEP_TAB::sort_table (this=0x7f5c9493e5d0) at /data/Code/mysql-server/sql/sql_executor.cc:2625
#6  0x00000000014e2246 in join_init_read_record (tab=0x7f5c9493e5d0) at /data/Code/mysql-server/sql/sql_executor.cc:2491
#7  0x00000000014df4ff in sub_select (join=0x7f5c9493d4e0, qep_tab=0x7f5c9493e5d0, end_of_records=false)
    at /data/Code/mysql-server/sql/sql_executor.cc:1284
#8  0x00000000014dee92 in do_select (join=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_executor.cc:957
#9  0x00000000014dcdf9 in JOIN::exec (this=0x7f5c9493d4e0) at /data/Code/mysql-server/sql/sql_executor.cc:206
#10 0x000000000157677b in handle_query (thd=0x7f5c94000b70, lex=0x7f5c94002ea0, result=0x7f5c94007658, added_options=0, removed_options=0)
    at /data/Code/mysql-server/sql/sql_select.cc:191
#11 0x000000000152bfe5 in execute_sqlcom_select (thd=0x7f5c94000b70, all_tables=0x7f5c94006e38)
    at /data/Code/mysql-server/sql/sql_parse.cc:5155
#12 0x0000000001525a1b in mysql_execute_command (thd=0x7f5c94000b70, first_level=true) at /data/Code/mysql-server/sql/sql_parse.cc:2828
---Type <return> to continue, or q <return> to quit---q
Quit

```

此处，不再是limit次数的调用了，ft_read 会被调用N次，
感觉应该是每一行匹配的都会read出来一下，估计最后再进行orderby
这应该是因为 limit 不再是对 where 的约束，而且对 where + orderby 的约束，where 不能够直接过滤数据了，需要对每一行数据都判定是否满足 where，所以需要多次 ft_read
这个时候也不会再调用 innobase_fts_find_ranking 函数，猜测是因为需要满足 where 条件时，已经通过 ft_read 拿到了所有的数据，以及rank，直接在内存里排序就可以了,


## fulltext 查询的一些特殊性

- 使用match函数会导致查询自动按照匹配的相关度进行排序，而不是默认的。

```sql
mysql> show create table tmp_z;
+-------+------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                         |
+-------+------------------------------------------------------------------------------------------------------+
| tmp_z | CREATE TABLE `tmp_z` (
  `a` text,
  FULLTEXT KEY `idx` (`a`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 |
+-------+------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)

mysql> select * from tmp_z;
+---------------------+
| a                   |
+---------------------+
| good monr           |
| good monr monr      |
| good monr monr monr |
+---------------------+
3 rows in set (0.00 sec)

mysql> select * from tmp_z where match(a) against('monr');
+---------------------+
| a                   |
+---------------------+
| good monr monr monr |
| good monr monr      |
| good monr           |
+---------------------+
3 rows in set (0.00 sec)
```

这其实是因为调用 ft_read 函数时，内部会进行自动排序，将 fts_query 中获取的信息（一颗以docId排序的红黑树）转换为一颗以rank排序的红黑树，然后一次返回一条最大的。

## 未解决的疑问

1. FTS_NO_RANKING 是什么情况下才会配置？会不会和innodb存储引擎无关
