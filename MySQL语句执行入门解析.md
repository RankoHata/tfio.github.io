# MySQL语句执行入门解析

> 只简单介绍基本逻辑，不进行任何复杂逻辑分析

## 基本的结构

### class THD

![THD](/img/class_THD.png)

> For each client connection we create a separate thread with THD serving as a thread/connection descriptor

THD 也就是 thread descriptor

其内部最核心的两个成员:
lex: 维护者sql语句的信息; 
dd_client 方法: 对外提供 data dictionary client 的接口，用于操作元数据(写入/读取都是调用这个 client 操作)

```cpp
 public:
  LEX *lex;                                        // parse tree descriptor
  dd::cache::Dictionary_client *dd_client() const  // Get the dictionary client.
  {
    return m_dd_client.get();
  }
```

### struct LEX

![LEX](/img/struct_LEX.png)

> The LEX object is strictly a part of class Sql_cmd, for those SQL commands that are represented by an Sql_cmd class. For the remaining SQL commands, it is a standalone object linked to the current THD.

LEX 简单来说是个存储解析SQL信息的结构

其继承 Query_tables_list,内部存着需要使用的表(Table_ref *query_tables),对于存储过程等,也有对应的 sroutines_list,用于存储需要的 routines

其内部还存储着 Sql_cmd *m_sql_cmd;
Sql_cmd就是在 parse_sql 过程中生成的 sql语句结构

### class Parse_tree_root

![Parse_tree_root](/img/classParse__tree__root__inherit__graph_org.svg)

> Base class for all top-level nodes of SQL statements

SQL语句顶层节点基类

SQL语句词语法解析最终生成的顶层节点，一定是其子类。

常见的比如 PT_select_stmt 就是 select 语句对应的顶层节点, PT就是 Parse_tree 的缩写

就一个虚方法 make_cmd, 就是将 PT_XXX 类转化成 Sql_cmd 类, 填充一些上下文的信息, 比如调用存储过程, 需要将存储过程名存入 thd 中, 用于后续逻辑中根据名字查找对应的元数据信息

```cpp
virtual Sql_cmd *make_cmd(THD *thd) = 0;
```

### class Sql_cmd

![Sql_cmd](/img/classSql__cmd__inherit__graph_org.svg)

> Representation of an SQL command.
This class is an interface between the parser and the runtime.
The parser builds the appropriate derived classes of Sql_cmd
to represent a SQL statement in the parsed tree.
The execute() method in the derived classes of Sql_cmd contain the runtime implementation.

几个核心的虚方法

```cpp
virtual enum_sql_command sql_command_code() const = 0;  // 返回类型，在gdb的时候可以根据这个进行强转
virtual bool prepare(THD *);  // 准备流程
virtual bool execute(THD *thd) = 0;  // 执行流程
virtual void cleanup(THD *);  // 清理流程
```

对于普通的 select 语句, 其对应的就是 Sql_cmd_select 类, 继承于 Sql_cmd_dml

Sql_cmd_dml 的几个核心虚方法

```cpp
virtual bool precheck(THD *thd) = 0;  // 执行预先检查
virtual bool check_privileges(THD *thd) = 0; // 校验权限
virtual bool prepare_inner(THD *thd) = 0;  // 这个就是模板方法, prepare内部会调用prepare_inner方法
virtual bool execute_inner(THD *thd);  // 同上
```

## SQL语句执行简要逻辑

![dispatch_sql_command](/img/dispatch_sql_command.png)

parse_sql 主要功能为分析SQL语句

MYSQLparse 是通过 yacc 工具生成的解析函数, 可以将SQL语句字符串解析成相应的数据结构 Parse_tree_root, 也就是 PT_xxx 类

LEX::make_sql_cmd 则是调用 root 的唯一虚方法, 生成 Sql_cmd 的具体业务子类

mysql_execute_command 则是核心的执行逻辑(在这之前其实还有查询重写/优化器相关逻辑, 其逻辑后续补充), 其逻辑就是一个超大 switch-case 语句, 根据不同的语句enum类型, 执行不同的逻辑, 大部分都是直接调用 execute 方法

prepare 方法一般是进行各种预先的校验/加载, 比如是否有权限执行对应的语句, 加载需要使用的表/routine(设置相关的cache逻辑也在此处)

execute 就是实际执行的逻辑, 待后续补充

### GDB堆栈参考

```cpp
make_cmd方法堆栈
#0  PT_select_stmt::make_cmd (this=0x7fba0c2a7788, thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/parse_tree_nodes.cc:703
#1  0x00000000034107d5 in LEX::make_sql_cmd (this=0x7fba0c00b8a0, parse_tree=0x7fba0c2a7788)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_lex.cc:4949
#2  0x000000000336bff7 in THD::sql_parser (this=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_class.cc:3066
#3  0x00000000034617fd in parse_sql (thd=0x7fba0c159140, parser_state=0x7fba4c6f5910, creation_ctx=0x0)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:7132
#4  0x000000000345cc21 in dispatch_sql_command (thd=0x7fba0c159140, parser_state=0x7fba4c6f5910)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:5265
#5  0x0000000003452fa3 in dispatch_command (thd=0x7fba0c159140, com_data=0x7fba4c6f6a00, command=COM_QUERY)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:2054
#6  0x0000000003450eef in do_command (thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:1439
#7  0x0000000003670cf5 in handle_connection (arg=0xbc5a170)
    at /home/sanmu/Code/mysql-server-8.0/sql/conn_handler/connection_handler_per_thread.cc:302
#8  0x00000000056432d4 in pfs_spawn_thread (arg=0xbd2f9f0) at /home/sanmu/Code/mysql-server-8.0/storage/perfschema/pfs.cc:3042
#9  0x00007fba9ad43ea5 in start_thread () from /lib64/libpthread.so.0
#10 0x00007fba9976b96d in clone () from /lib64/libc.so.6

prepare方法堆栈
#0  Sql_cmd_dml::prepare (this=0x7fba0cc3a7d8, thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_select.cc:495
#1  0x00000000034dd938 in Sql_cmd_dml::execute (this=0x7fba0cc3a7d8, thd=0x7fba0c159140)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_select.cc:718
#2  0x000000000345af79 in mysql_execute_command (thd=0x7fba0c159140, first_level=true)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:4719
#3  0x000000000345d217 in dispatch_sql_command (thd=0x7fba0c159140, parser_state=0x7fba4c6f5910)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:5368
#4  0x0000000003452fa3 in dispatch_command (thd=0x7fba0c159140, com_data=0x7fba4c6f6a00, command=COM_QUERY)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:2054
#5  0x0000000003450eef in do_command (thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:1439
#6  0x0000000003670cf5 in handle_connection (arg=0xbc5a170)
    at /home/sanmu/Code/mysql-server-8.0/sql/conn_handler/connection_handler_per_thread.cc:302
#7  0x00000000056432d4 in pfs_spawn_thread (arg=0xbd2f9f0) at /home/sanmu/Code/mysql-server-8.0/storage/perfschema/pfs.cc:3042
#8  0x00007fba9ad43ea5 in start_thread () from /lib64/libpthread.so.0
#9  0x00007fba9976b96d in clone () from /lib64/libc.so.6

execute方法堆栈
#0  Sql_cmd_dml::execute_inner (this=0x7fba0cc3a7d8, thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_select.cc:1005
#1  0x00000000034ddde1 in Sql_cmd_dml::execute (this=0x7fba0cc3a7d8, thd=0x7fba0c159140)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_select.cc:793
#2  0x000000000345af79 in mysql_execute_command (thd=0x7fba0c159140, first_level=true)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:4719
#3  0x000000000345d217 in dispatch_sql_command (thd=0x7fba0c159140, parser_state=0x7fba4c6f5910)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:5368
#4  0x0000000003452fa3 in dispatch_command (thd=0x7fba0c159140, com_data=0x7fba4c6f6a00, command=COM_QUERY)
    at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:2054
#5  0x0000000003450eef in do_command (thd=0x7fba0c159140) at /home/sanmu/Code/mysql-server-8.0/sql/sql_parse.cc:1439
#6  0x0000000003670cf5 in handle_connection (arg=0xbc5a170)
    at /home/sanmu/Code/mysql-server-8.0/sql/conn_handler/connection_handler_per_thread.cc:302
#7  0x00000000056432d4 in pfs_spawn_thread (arg=0xbd2f9f0) at /home/sanmu/Code/mysql-server-8.0/storage/perfschema/pfs.cc:3042
#8  0x00007fba9ad43ea5 in start_thread () from /lib64/libpthread.so.0
#9  0x00007fba9976b96d in clone () from /lib64/libc.so.6
```