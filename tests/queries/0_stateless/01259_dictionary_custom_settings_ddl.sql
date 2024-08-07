-- Tags: no-fasttest

CREATE TABLE table_for_dict
(
  key_column UInt64,
  second_column UInt64,
  third_column String
)
ENGINE = MergeTree()
ORDER BY key_column;

INSERT INTO table_for_dict VALUES (100500, 10000000, 'Hello world');

DROP DATABASE IF EXISTS ordinary_db;

CREATE DATABASE ordinary_db;

DROP DICTIONARY IF EXISTS ordinary_db.dict1;

CREATE DICTIONARY ordinary_db.dict1
(
  key_column UInt64 DEFAULT 0,
  second_column UInt64 DEFAULT 1,
  third_column String DEFAULT 'qqq'
)
PRIMARY KEY key_column
SOURCE(CLICKHOUSE(HOST 'localhost' PORT tcpPort() USER 'default' TABLE 'table_for_dict' PASSWORD '' DB currentDatabase()))
LIFETIME(MIN 1 MAX 10)
LAYOUT(FLAT()) SETTINGS(max_result_bytes=1);

SELECT 'INITIALIZING DICTIONARY';

SELECT dictGetUInt64('ordinary_db.dict1', 'second_column', toUInt64(100500)); -- { serverError TOO_MANY_ROWS_OR_BYTES }

SELECT 'END';

DROP DATABASE IF EXISTS ordinary_db;

DROP TABLE IF EXISTS table_for_dict;
