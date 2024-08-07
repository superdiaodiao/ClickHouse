#!/usr/bin/env bash
# Tags: no-fasttest
# Tag no-fasttest: 45 seconds running

# Creation of a database with Ordinary engine emits a warning.
CLICKHOUSE_CLIENT_SERVER_LOGS_LEVEL=fatal

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh


$CLICKHOUSE_CLIENT -nm -q "
DROP DATABASE IF EXISTS test_01114_1;
DROP DATABASE IF EXISTS test_01114_2;
DROP DATABASE IF EXISTS test_01114_3;
"

$CLICKHOUSE_CLIENT --allow_deprecated_database_ordinary=0 -q "CREATE DATABASE test_01114_1 ENGINE=Ordinary" 2>&1| grep -Fac "UNKNOWN_DATABASE_ENGINE"

$CLICKHOUSE_CLIENT -q "CREATE DATABASE test_01114_1 ENGINE=Atomic"
$CLICKHOUSE_CLIENT -q "CREATE DATABASE test_01114_2"
$CLICKHOUSE_CLIENT --allow_deprecated_database_ordinary=1 -q "CREATE DATABASE test_01114_3 ENGINE=Ordinary"

$CLICKHOUSE_CLIENT --show_table_uuid_in_table_create_query_if_not_nil=0 -q "SHOW CREATE DATABASE test_01114_1"
$CLICKHOUSE_CLIENT --show_table_uuid_in_table_create_query_if_not_nil=0 -q "SHOW CREATE DATABASE test_01114_2"
$CLICKHOUSE_CLIENT -q "SHOW CREATE DATABASE test_01114_3"

uuid_db_1=`$CLICKHOUSE_CLIENT -q "SELECT uuid FROM system.databases WHERE name='test_01114_1'"`
uuid_db_2=`$CLICKHOUSE_CLIENT -q "SELECT uuid FROM system.databases WHERE name='test_01114_2'"`
$CLICKHOUSE_CLIENT -q "SELECT name,
                              engine,
                              splitByChar('/', data_path)[-2],
                              splitByChar('/', metadata_path)[-2] as uuid_path, ((splitByChar('/', metadata_path)[-3] as metadata) = substr(uuid_path, 1, 3)) OR metadata='metadata'
                              FROM system.databases WHERE name LIKE 'test_01114_%'" | sed "s/$uuid_db_1/00001114-1000-4000-8000-000000000001/g" | sed "s/$uuid_db_2/00001114-1000-4000-8000-000000000002/g"

$CLICKHOUSE_CLIENT -nm -q "
CREATE TABLE test_01114_1.mt_tmp (n UInt64) ENGINE=MergeTree() ORDER BY tuple();
INSERT INTO test_01114_1.mt_tmp SELECT * FROM numbers(100);
CREATE TABLE test_01114_3.mt (n UInt64) ENGINE=MergeTree() ORDER BY tuple() PARTITION BY (n % 5);
INSERT INTO test_01114_3.mt SELECT * FROM numbers(110);

RENAME TABLE test_01114_1.mt_tmp TO test_01114_3.mt_tmp; /* move from Atomic to Ordinary */
RENAME TABLE test_01114_3.mt TO test_01114_1.mt;         /* move from Ordinary to Atomic */
SELECT count() FROM test_01114_1.mt;
SELECT count() FROM test_01114_3.mt_tmp;

DROP DATABASE test_01114_3;
"

explicit_uuid=$($CLICKHOUSE_CLIENT -q "SELECT generateUUIDv4()")
$CLICKHOUSE_CLIENT -q "CREATE TABLE test_01114_2.mt UUID '$explicit_uuid' (n UInt64) ENGINE=MergeTree() ORDER BY tuple() PARTITION BY (n % 5)"
$CLICKHOUSE_CLIENT --show_table_uuid_in_table_create_query_if_not_nil=1 -q "SHOW CREATE TABLE test_01114_2.mt" | sed "s/$explicit_uuid/00001114-0000-4000-8000-000000000002/g"
$CLICKHOUSE_CLIENT -q "SELECT name, uuid, create_table_query FROM system.tables WHERE database='test_01114_2'" | sed "s/$explicit_uuid/00001114-0000-4000-8000-000000000002/g"


$CLICKHOUSE_CLIENT --function_sleep_max_microseconds_per_block 60000000 -q "SELECT count(col), sum(col) FROM (SELECT n + sleepEachRow(1.5) AS col FROM test_01114_1.mt)" &     # 33s (1.5s * 22 rows per partition), result: 110, 5995
$CLICKHOUSE_CLIENT --function_sleep_max_microseconds_per_block 60000000 -q "INSERT INTO test_01114_2.mt SELECT number + sleepEachRow(1.5) FROM numbers(30)" &                  # 45s (1.5s * 30 rows)
sleep 1   # SELECT and INSERT should start before the following RENAMEs

$CLICKHOUSE_CLIENT -nm -q "
RENAME TABLE test_01114_1.mt TO test_01114_1.mt_tmp;
RENAME TABLE test_01114_1.mt_tmp TO test_01114_2.mt_tmp;
EXCHANGE TABLES test_01114_2.mt AND test_01114_2.mt_tmp;
RENAME TABLE test_01114_2.mt_tmp TO test_01114_1.mt;
EXCHANGE TABLES test_01114_1.mt AND test_01114_2.mt;
"

# Check that nothing changed
$CLICKHOUSE_CLIENT -q "SELECT count() FROM test_01114_1.mt"
uuid_mt1=$($CLICKHOUSE_CLIENT -q "SELECT uuid FROM system.tables WHERE database='test_01114_1' AND name='mt'")
$CLICKHOUSE_CLIENT --show_table_uuid_in_table_create_query_if_not_nil=1 -q "SHOW CREATE TABLE test_01114_1.mt" | sed "s/$uuid_mt1/00001114-0000-4000-8000-000000000001/g"
$CLICKHOUSE_CLIENT --show_table_uuid_in_table_create_query_if_not_nil=1 -q "SHOW CREATE TABLE test_01114_2.mt" | sed "s/$explicit_uuid/00001114-0000-4000-8000-000000000002/g"

$CLICKHOUSE_CLIENT -nm -q "
DROP TABLE test_01114_1.mt SETTINGS database_atomic_wait_for_drop_and_detach_synchronously=0;
CREATE TABLE test_01114_1.mt (s String) ENGINE=Log();
INSERT INTO test_01114_1.mt SELECT 's' || toString(number) FROM numbers(5);
SELECT count() FROM test_01114_1.mt
" # result: 5

$CLICKHOUSE_CLIENT --function_sleep_max_microseconds_per_block 60000000 -q "SELECT tuple(s, sleepEachRow(3)) FROM test_01114_1.mt" > /dev/null &    # 15s (3s * 5 rows)
sleep 1
$CLICKHOUSE_CLIENT -q "DROP DATABASE test_01114_1" --database_atomic_wait_for_drop_and_detach_synchronously=0 && echo "dropped"

wait # for INSERT and SELECT

$CLICKHOUSE_CLIENT -q "SELECT count(n), sum(n) FROM test_01114_2.mt"    # result: 30, 435
$CLICKHOUSE_CLIENT -q "DROP DATABASE test_01114_2" --database_atomic_wait_for_drop_and_detach_synchronously=0
