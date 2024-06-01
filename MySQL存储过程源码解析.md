# Store Procedure

## sp_instr 类

![sp_instr类图](img\sp_instr_class.png)

[类图官网链接](https://dev.mysql.com/doc/dev/mysql-server/8.3.0/classsp__instr.html)

### 简单介绍

sp_instr: 存储过程指令基类

sp_lex_instr: 初始化需要 LEX 对象，用于解析表达式（内部涉及其他SQL表达式的，都需要继承这个类，因为要在运行过程中执行对应的SQL）

> sp_lex_instr keeps LEX-object to be able to evaluate the expression.

sp_lex_branch_instr: 在 lex_instr 基础上添加了跳转能力，执行SQL语句，计算结果，判定跳转

> sp_lex_branch_instr is a base class for SP-instructions, which might perform conditional jump depending on the value of an SQL-expression.

## keyword

sp - store procedure  存储过程
instr - instruction  指令