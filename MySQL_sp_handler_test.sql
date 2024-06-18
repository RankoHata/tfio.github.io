-- case when test case 1
-- case expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(3);
      END;
    CASE xxx(1)
      WHEN 1 THEN INSERT INTO t1 VALUES(1);
      ELSE
        BEGIN
          INSERT INTO t1 VALUES(2);
        END;
    END CASE;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;

-- case when test case 2
-- when expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(3);
      END;
    CASE 1
      WHEN xxx(1) THEN INSERT INTO t1 VALUES(1);
      ELSE
        BEGIN
          INSERT INTO t1 VALUES(2);
        END;
    END CASE;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;

-- case when test case 3
-- search case statement, when expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(3);
      END;
    CASE
      WHEN xxx(1) THEN INSERT INTO t1 VALUES(1);
      ELSE
        BEGIN
          INSERT INTO t1 VALUES(2);
        END;
    END CASE;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;

-- while test case 1
-- while expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(3);
      END;
    WHILE xxx(1) DO
      INSERT INTO t1 VALUES(1);
    END WHILE;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;

-- if test case 1
-- if expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(5);
      END;
    IF xxx(1) THEN
      INSERT INTO t1 VALUES(1);
    ELSEIF 1 THEN
      INSERT INTO t1 VALUES(2);
    ELSE
      INSERT INTO t1 VALUES(3);  
    END IF;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;

-- if test case 2
-- else if expr error.
-- ERROR 1305 (42000): FUNCTION test.xxx does not exist

DELIMITER |
DROP PROCEDURE IF EXISTS P|
DROP TABLE IF EXISTS t1|
CREATE TABLE t1(a int)|
CREATE PROCEDURE p()
  BEGIN
    DECLARE CONTINUE HANDLER FOR 1305
      BEGIN
        INSERT INTO t1 VALUES(5);
      END;
    IF 0 THEN
      INSERT INTO t1 VALUES(1);
    ELSEIF xxx(1) THEN
      INSERT INTO t1 VALUES(2);
    ELSE
      INSERT INTO t1 VALUES(3);  
    END IF;
    INSERT INTO t1 VALUES(4);
  END;
|

CALL p()|
SELECT * FROM t1|
DELIMITER ;
