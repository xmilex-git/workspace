# 결함 다발 부류 탐침 — develop cad27172b optdebug (자동 생성)

셀 = 첫 결과 행(타입은 축약) / `ERR:분류` / `∅`(0행) / `·`(측정 없음, 크래시로 건너뜀 포함). 바인드 값: string '1.0', strdate '2024-01-02', strtime '10:00:01', int 1, bigint 9007199254740993, numeric 1.50, double 1.5, date 2024-01-02, datetime 2024-01-02 10:00:01.500, time 10:00:01.


#### AGG.hv

| 문맥 \ bind | null | string | strdate | int | bigint | numeric | double | date | time | datetime |
|---|---|---|---|---|---|---|---|---|---|---|
| `sum` | '*NULL*' NULL | dbl 5.000000000000000e+00 | ERR:coerce | int 5 | bigint 45035996273704965 | num(10,2) 7.50 | dbl 7.500000000000000e+00 | ERR:Invalid_data_type_referenced | time 10:00:01 AM | dtt 10:00:01.500 AM 01/02/ |
| `sum_group` | 1 '*NULL*' NULL (+2행) | 1 'double' 2.0000000000000 (+2행) | ERR:coerce | 1 'integer' 2 (+2행) | 1 'bigint' 180143985094819 (+2행) | 1 'numeric (10, 2)' 3.00 (+2행) | 1 'double' 3.0000000000000 (+2행) | ERR:Invalid_data_type_referenced | 1 'time' 10:00:01 AM (+2행) | 1 'datetime' 10:00:01.500  (+2행) |
| `min` | '*NULL*' NULL NULL | varchar '1.0' '1.0' | varchar '2024-01-02' '2024 | int 1 1 | bigint 9007199254740993 90 | num(10,2) 1.50 1.50 | dbl 1.500000000000000e+00  | date 01/02/2024 01/02/2024 | time 10:00:01 AM 10:00:01  | dtt 10:00:01.500 AM 01/02/ |
| `avg` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:coerce | dbl 1.000000000000000e+00 | dbl 9.007199254740994e+15 | dbl 1.500000000000000e+00 | dbl 1.500000000000000e+00 | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `count_distinct` | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| `median` | '*NULL*' NULL | dbl 1.000000000000000e+00 | dtt 12:00:00.000 AM 01/02/ | dbl 1.000000000000000e+00 | dbl 9.007199254740992e+15 | dbl 1.500000000000000e+00 | dbl 1.500000000000000e+00 | date 01/02/2024 | time 10:00:01 AM | dtt 10:00:01.500 AM 01/02/ |
| `pcont_order` | NULL | 1.000000000000000e+00 | 12:00:00.000 AM 01/02/2024 | 1.000000000000000e+00 | 9.007199254740992e+15 | 1.500000000000000e+00 | 1.500000000000000e+00 | 01/02/2024 | 10:00:01 AM | 10:00:01.500 AM 01/02/2024 |
| `sum_i_plus` | 1 '*NULL*' NULL (+2행) ; NULL | 1 'double' 5.0000000000000 (+2행) | ERR:coerce | ERR:overflow | 1 'bigint' 180143985094819 (+2행) | 1 'numeric' 6.00 (+2행) | 1 'double' 6.0000000000000 (+2행) | ERR:overflow | 1 'time' 10:00:03 AM (+2행) | 1 'datetime' 10:00:01.502  (+2행) |
| `group_by_expr` | NULL 5 ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 | NULL 1 (+4행) ; NULL | NULL ; ERR:coerce | NULL ; ERR:overflow | NULL 1 (+4행) ; NULL | NULL 1 (+4행) ; NULL | NULL 1 (+4행) ; NULL | NULL ; ERR:overflow | NULL 1 (+4행) ; NULL | NULL 1 (+4행) ; NULL |
| `group_by_slot` | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; NULL ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; NULL ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; NULL ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; NULL ; ERR:Semantic____can_not_be_a_GRO ; ERR:A_prepared_statement_with_th |
| `having` | 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:coerce | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:coerce | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:overflow | 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:coerce |
| `group_concat` | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | '1.0,1.0,1.0,1.0,1.0' ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '2024-01-02,2024-01-02,202 ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | '1,1,1,1,1' ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '9007199254740993,90071992 ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '1.50,1.50,1.50,1.50,1.50' ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '1.5,1.5,1.5,1.5,1.5' ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '01/02/2024,01/02/2024,01/ ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | '10:00:01 AM,10:00:01 AM,1 ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | '10:00:01.500 AM 01/02/202 ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 |
| `group_concat_plus` | NULL | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM |
| `sum_over` | 1 NULL (+4행) | 1 2.000000000000000e+00 (+4행) | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 1 2 (+4행) | 1 18014398509481986 (+4행) | 1 3.00 (+4행) | 1 3.000000000000000e+00 (+4행) | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} |
| `max_over` | '*NULL*' NULL (+4행) | varchar '1.0' (+4행) | varchar '2024-01-02' (+4행) | int 1 (+4행) | bigint 9007199254740993 (+4행) | num(10,2) 1.50 (+4행) | dbl 1.500000000000000e+00 (+4행) | date 01/02/2024 (+4행) | time 10:00:01 AM (+4행) | dtt 10:00:01.500 AM 01/02/ (+4행) |
| `lead` | '*NULL*' NULL (+4행) | varchar '1.0' (+4행) | varchar '2024-01-02' (+4행) | int 1 (+4행) | bigint 9007199254740993 (+4행) | num(10,2) 1.50 (+4행) | dbl 1.500000000000000e+00 (+4행) | date 01/02/2024 (+4행) | time 10:00:01 AM (+4행) | dtt 10:00:01.500 AM 01/02/ (+4행) |
| `nth_value` | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) | NULL (+4행) |
| `first_value` | '*NULL*' NULL (+4행) | varchar '1.0' (+4행) | varchar '2024-01-02' (+4행) | int 1 (+4행) | bigint 9007199254740993 (+4행) | num(10,2) 1.50 (+4행) | dbl 1.500000000000000e+00 (+4행) | date 01/02/2024 (+4행) | time 10:00:01 AM (+4행) | dtt 10:00:01.500 AM 01/02/ (+4행) |
| `ntile` | NULL (+4행) | 1 (+4행) | ERR:coerce | 1 (+4행) | ERR:Invalid_bucket_number_for_NT | 1 (+4행) | 1 (+4행) | ERR:coerce | ERR:coerce | ERR:coerce |
| `order_by_slot` | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th | ERR:Semantic____can_not_be_an_OR ; ERR:A_prepared_statement_with_th |
| `distinct` | NULL | '1.0' | '2024-01-02' | 1 | 9007199254740993 | 1.50 | 1.500000000000000e+00 | 01/02/2024 | 10:00:01 AM | 10:00:01.500 AM 01/02/2024 |
| `max_str_to_date_over` | NULL (+1행) | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `rollup` | 1 NULL (+3행) | 1 5.000000000000000e+00 (+3행) | ERR:coerce | ERR:overflow | 1 18014398509481989 (+3행) | 1 6.00 (+3행) | 1 6.000000000000000e+00 (+3행) | ERR:overflow | 1 10:00:03 AM (+3행) | 1 10:00:01.502 AM 01/02/20 (+3행) |
| `hash_agg` | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th | ERR:Semantic_before___sumi_from ; ERR:A_prepared_statement_with_th |

#### FN

| 문맥 \ bind | null | string | strdate | int | bigint | numeric | double | date | time | datetime |
|---|---|---|---|---|---|---|---|---|---|---|
| `str_to_date_val` | '*NULL*' NULL | ERR:Function_called_with_missing | date 01/02/2024 | date 01/01/0001 | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `str_to_date_fmt` | '*NULL*' NULL | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `str_to_date_both` | NULL | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `str_to_date_derived_cmp` | ∅ | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `str_to_date_derived_order` | NULL (+1행) | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `to_char_fmt_date` | NULL | '1.0' | '2024-01-02' | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | '2024-01-02' | ERR:Invalid_format | '2024-01-02' |
| `to_char_fmt_num` | NULL | '1.0' | '2024-01-02' | ' 1.00' | '########' ; NULL | ' 1.50' | ' 1.50' | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format |
| `to_char_fmt_hv` | NULL | '1.0' | '2024-01-02' | ERR:Invalid_format | '1.0' ; '2024-01-02' ; '10:00:01' ; 1 ; ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | '2024-01-02' | ERR:Invalid_format | '2024-01-02' |
| `to_char_fmt_hv_num` | NULL | '1.0' | '2024-01-02' | ' 1.00' | '########' ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | ' 1.50' | ' 1.50' | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format |
| `to_char_bare` | NULL | '1.0' | '2024-01-02' | '1' | '9007199254740993' ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | '1.5' | '1.5' | '01/02/2024' | '10:00:01 AM' | '10:00:01.500 AM 01/02/202 |
| `to_char_col_fmt_hv` | NULL (+1행) | ERR:Invalid_format | ERR:Invalid_format | ERR:Empty_string_not_allowed_her | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | ERR:Empty_string_not_allowed_her | ERR:Empty_string_not_allowed_her | ERR:Empty_string_not_allowed_her | ERR:Empty_string_not_allowed_her | ERR:Empty_string_not_allowed_her |
| `to_date` | NULL | ERR:Invalid_format | 01/02/2024 | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format |
| `to_date_fmt_hv` | NULL | ERR:Invalid_format | 01/02/2024 | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format |
| `to_datetime` | NULL | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format |
| `to_number` | '*NULL*' NULL | ERR:There_are_some_mismatches_be | ERR:There_are_some_mismatches_be | numeric 1 | numeric 9007199254740993 | ERR:There_are_some_mismatches_be | ERR:There_are_some_mismatches_be | ERR:There_are_some_mismatches_be | ERR:There_are_some_mismatches_be | ERR:There_are_some_mismatches_be |
| `addtime_val` | '*NULL*' NULL | varchar '01:00:01 AM' | varchar '01:00:00.000 AM 0 | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | dtt 01:00:00.000 AM 01/02/ | time 11:00:01 AM | dtt 11:00:01.500 AM 01/02/ |
| `addtime_both` | NULL | '12:00:02 AM' | · | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | · | ERR:Invalid_data_type_The_argume | · | 08:00:02 PM | 08:00:02.500 PM 01/02/2024 |
| `from_tz` | NULL | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | 10:00:01.500 AM 01/02/2024 |
| `from_tz_both` | NULL | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | 10:00:01.500 AM 01/02/2024 |
| `new_time` | NULL | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | 01:00:01 AM | 01:00:01.500 AM 01/02/2024 |
| `new_time_all` | NULL | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | 01:00:01 AM | 01:00:01.500 AM 01/02/2024 |
| `date_add` | '*NULL*' NULL | ERR:Conversion_error_in_date_for | varchar '01/03/2024' | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Conversion_error_in_date_for | varchar '01/06/2026' | varchar '01/03/2024' | ERR:Function_called_with_missing | varchar '10:00:01.500 AM 0 |
| `date_add_hv_n` | NULL | 01/02/2024 | · | 01/02/2024 | ERR:Function_called_with_missing | 01/03/2024 | 01/03/2024 | · | · | · |
| `adddate` | NULL | ERR:Function_called_with_missing | '01/03/2024' | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | '01/06/2026' | '01/03/2024' | ERR:Function_called_with_missing | '10:00:01.500 AM 01/03/202 |
| `hour` | NULL NULL NULL | 0 0 1 | ERR:Conversion_error_in_time_for | ERR:Conversion_error_in_time_for | ERR:Conversion_error_in_time_for | ERR:Conversion_error_in_time_for | ERR:Conversion_error_in_time_for | ERR:Conversion_error_in_time_for | 10 0 1 | 10 0 1 |
| `extract` | NULL | ERR:Invalid_data_type_referenced | 2024 | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | 2024 | 32765 | 2024 |
| `datediff` | NULL | · | 1 | · | · | · | · | 1 | · | 1 |
| `timediff` | NULL | ERR:Conversion_error_in_time_for | · | ERR:Conversion_error_in_time_for | 06:36:33 AM | · | ERR:Conversion_error_in_time_for | · | 09:00:01 AM | 09:00:01 AM |
| `unix_timestamp` | NULL | ERR:Function_called_with_missing | 1704121200 | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | 1767538800 | 1704121200 | ERR:Function_called_with_missing | 1704157201 |
| `trunc_default` | NULL | 1.000000000000000e+00 | ERR:Invalid_data_type_referenced | 1 | 9007199254740993 | 1.00 | 1.000000000000000e+00 | 01/02/2024 | ERR:Invalid_data_type_referenced | 01/02/2024 |
| `trunc_num` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:Invalid_data_type_referenced | int 1 | bigint 9007199254740993 | numeric 1.00 | dbl 1.000000000000000e+00 | date 01/02/2024 | ERR:Invalid_data_type_referenced | date 01/02/2024 |
| `round` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:Invalid_data_type_referenced | int 1 | bigint 9007199254740992 | numeric 1.50 | dbl 1.500000000000000e+00 | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_The_argume |
| `abs` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:coerce | int 1 | bigint 9007199254740993 | num(10,2) 1.50 | dbl 1.500000000000000e+00 | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `ceil` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:coerce | int 1 | bigint 9007199254740993 | numeric 2.00 | dbl 2.000000000000000e+00 | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `hex` | NULL | '312E30' | '323032342D30312D3032' | '1' | '20000000000001' | '2' | '2' | '30312F30322F32303234' | '31303A30303A303120414D' | '31303A30303A30312E3530302 |
| `conv` | NULL | '1' | ERR:Function_called_with_missing | '1' | '1000000000000000000000000 | '1' | '10' | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume |
| `ascii` | NULL | 49 | 50 | 49 | 57 | 49 | 49 | 48 | 49 | 49 |
| `bit_length` | NULL NULL | 24 3 | 80 10 | 8 1 | 128 16 | 32 4 | 24 3 | 80 10 | 88 11 | 208 26 |
| `repeat_plus_abs` | NULL | '1.01.0' | ERR:coerce | '2' | ERR:overflow | '3.003.00' | '33' | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `insert_str` | NULL | 'xybcdef' | · | 'xybcdef' | · | 'axydef' | 'axydef' | · | · | · |
| `elt` | NULL | 'a' | · | 'a' | NULL | 'b' | 'b' | · | · | · |
| `field` | 0 | 1 | 0 | 1 | 0 | 3 | 3 | 0 | 0 | 0 |
| `decode_empty` | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th | ERR:coerce ; ERR:A_prepared_statement_with_th |
| `decode_str` | 'N' | 'Z' | 'Z' | 'Z' | 'Z' | 'Z' | 'Z' | ERR:coerce | 'Z' | ERR:coerce |
| `ifnull_1` | int 1 | varchar '1.0' | varchar '2024-01-02' | int 1 | bigint 9007199254740993 | numeric 1.50 | dbl 1.500000000000000e+00 | varchar '01/02/2024' | varchar '10:00:01 AM' | varchar '10:00:01.500 AM 0 |
| `nvl2` | char 'x' | char '1' | char '1' | char '1' | char '1' | char '1' | char '1' | char '1' | char '1' | char '1' |
| `nullif` | '*NULL*' NULL | '*NULL*' NULL | varchar '2024-01-02' | '*NULL*' NULL | varchar '9007199254740993' | varchar '1.50' | varchar '1.5' | varchar '01/02/2024' | varchar '10:00:01 AM' | varchar '10:00:01.500 AM 0 |
| `greatest` | '*NULL*' NULL | char 'b' | char 'b' | char 'b' | char 'b' | char 'b' | char 'b' | char 'b' | char 'b' | char 'b' |
| `least_hv` | '*NULL*' NULL | varchar '1.0' | varchar '1' | varchar '1' | varchar '1' | varchar '1' | varchar '1' | varchar '1' | varchar '1' | varchar '1' |
| `coalesce_cast_chain` | '*NULL*' NULL | varchar '1.0' | varchar '2024-01-02' | int 1 | bigint 9007199254740993 | num(10,2) 1.50 | dbl 1.500000000000000e+00 | date 01/02/2024 | time 10:00:01 AM | dtt 10:00:01.500 AM 01/02/ |
| `if_cond` | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th | ERR:Syntax_before___T_F__operand ; ERR:A_prepared_statement_with_th |
| `case_slot_when` | 'else' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' |
| `case_when_slot_lit` | 'else' | 'one' | ERR:coerce | 'one' | 'else' | 'else' | 'else' | ERR:coerce | ERR:coerce | ERR:coerce |
| `decode_slot` | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' | 'first' |
| `orderby_num` | ERR:Invalid_data_type_referenced | NULL | ERR:coerce | NULL | NULL (+4행) | NULL | NULL | ERR:coerce | ERR:coerce | ERR:coerce |
| `limit` | ERR:Invalid_data_type_referenced | NULL | ERR:coerce | NULL | NULL (+4행) | NULL | NULL | ERR:coerce | ERR:coerce | ERR:coerce |
| `limit2` | ∅ | ERR:coerce | ERR:coerce | 1 | ∅ | 1 (+1행) | 1 (+1행) | ERR:Invalid_data_type_referenced | ∅ | ERR:coerce |
| `keylimit` | ERR:Invalid_data_type_referenced | 1 | ERR:coerce | 1 | 1 (+1행) | 1 (+1행) | 1 (+1행) | ERR:coerce | ERR:coerce | ERR:coerce |
| `keylimit2` | ERR:Invalid_data_type_referenced | 2 | ERR:coerce | 2 | ∅ | ∅ | ∅ | ERR:coerce | ERR:coerce | ERR:coerce |
| `in_multiset` | 0 | 5 | · | 5 | 0 | 0 | 0 | · | · | · |
| `in_list_mixed` | 2 | 2 | · | 2 | 2 | 2 | 2 | · | · | · |
| `in_set_hv` | 0 | · | · | · | · | · | · | · | · | · |
| `between` | 0 | 3 | ERR:coerce | 3 | 0 | 2 | 2 | ERR:coerce | 0 | ERR:coerce |
| `like` | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `like_both` | NULL | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| `concat_hv` | NULL NULL | '1.01.0' 'utf8_bin' | '2024-01-022024-01-02' 'ut | '11' 'utf8_bin' | '9007199254740993900719925 | '1.501.50' 'utf8_bin' | '1.51.5' 'utf8_bin' | '01/02/202401/02/2024' 'ut | '10:00:01 AM10:00:01 AM' ' | '10:00:01.500 AM 01/02/202 |
| `rtrim_plus` | NULL | '1.01.' | '2024-01-022024-01-02' | '2' | '18014398509481986' | '3.' | '3' | ERR:Invalid_data_type_referenced | NULL | NULL |
| `find_in_set_plus` | '1' NULL (+1행) | '1' 0 (+1행) | '1' 0 (+1행) | '1' 0 (+1행) | '1' 0 (+1행) | '1' 0 (+1행) | '1' 0 (+1행) | ERR:Invalid_data_type_referenced | '1' NULL (+1행) | '1' NULL (+1행) |
| `position_in` | NULL | 1 | 7 | 1 | 5 | 1 | 1 | 2 | 1 | 1 |
| `replace3` | NULL | 'x.0' | '2024-0x-02' | 'x' | '9007x99254740993' | 'x.50' | 'x.5' | '0x/02/2024' | 'x0:00:0x AM' | 'x0:00:0x.500 AM 0x/02/202 |
| `translate3` | NULL | 'x.0' | '2024-0x-02' | 'x' | '9007x99254740993' | 'x.50' | 'x.5' | '0x/02/2024' | 'x0:00:0x AM' | 'x0:00:0x.500 AM 0x/02/202 |
| `substring_index` | NULL | '1' | '2024-01-02' | '1' | '9007199254740993' | '1' | '1' | '01/02/2024' | '10:00:01 AM' | '10:00:01' |
| `lpad` | NULL | '**1.0' | '2024-' | '****1' | '90071' | '*1.50' | '**1.5' | '01/02' | '10:00' | '10:00' |
| `upper` | '*NULL*' NULL NULL | varchar '1.0' 'utf8_bin' | varchar '2024-01-02' 'utf8 | varchar '1' 'utf8_bin' | varchar '9007199254740993' | varchar '1.50' 'utf8_bin' | varchar '1.5' 'utf8_bin' | varchar '01/02/2024' 'utf8 | varchar '10:00:01 AM' 'utf | varchar '10:00:01.500 AM 0 |
| `eq_collation` | NULL NULL | 1 'utf8_bin' | 1 'utf8_bin' | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing | ERR:Function_called_with_missing |
| `json_extract` | NULL | NULL | ERR:Invalid_json_The_document_ro | ERR:Invalid_type_integer_Expecti | ERR:Invalid_type_bigint_Expectin | ERR:Invalid_type_numeric_Expecti | ERR:Invalid_type_double_Expectin | ERR:Invalid_type_date_Expecting | ERR:Invalid_type_time_Expecting | ERR:Invalid_type_datetime_Expect |
| `select_bare` | NULL | '1.0' | '2024-01-02' | 1 | 9007199254740993 | 1.50 | 1.500000000000000e+00 | 01/02/2024 | 10:00:01 AM | 10:00:01.500 AM 01/02/2024 |
| `select_typeof` | '*NULL*' | varchar | varchar | int | bigint | num(10,2) | dbl | date | time | dtt |
| `select_where_false` | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ |
| `plus_plus` | '*NULL*' NULL | varchar '1.01.0' | varchar '2024-01-022024-01 | int 2 | bigint 18014398509481986 | numeric 3.00 | dbl 3.000000000000000e+00 | ERR:Invalid_data_type_referenced | '*NULL*' NULL | '*NULL*' NULL |
| `plus_lit` | '*NULL*' NULL '*NULL*' NUL | dbl 2.000000000000000e+00  | ERR:coerce | int 2 'integer' 2 | bigint 9007199254740994 'b | numeric 2.50 'numeric' 2.5 | dbl 2.500000000000000e+00  | date 01/03/2024 'date' 01/ | time 10:00:02 AM 'time' 10 | dtt 10:00:01.501 AM 01/02/ |
| `minus_lit` | '*NULL*' NULL | dbl 0.000000000000000e+00 | ERR:coerce | int 0 | bigint 9007199254740992 | numeric 0.50 | dbl 5.000000000000000e-01 | date 01/01/2024 | time 10:00:00 AM | dtt 10:00:01.499 AM 01/02/ |
| `div_lit` | '*NULL*' NULL '*NULL*' NUL | dbl 7.000000000000000e+00  | ERR:coerce | int 7 'integer' 0 | bigint 0 'bigint' 45035996 | numeric 4.666666667 'numer | dbl 4.666666666666667e+00  | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `div_slot_slot` | '*NULL*' NULL | dbl 1.000000000000000e+00 | ERR:coerce | int 1 | bigint 1 | numeric 1.0000000000000000 | dbl 1.000000000000000e+00 | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `idiv_lit` | NULL NULL NULL | 7 0 0.000000000000000e+00 | · | 7 0 0 | 0 7 7 | 3 1 1.00 | 3 1 1.000000000000000e+00 | · | · | · |
| `date_minus` | '*NULL*' NULL (+1행) | ERR:coerce | bigint -86400000 (+1행) | date 12/31/2023 (+1행) | ERR:Date_arithmetic_underflow | date 12/30/2023 (+1행) | date 12/30/2023 (+1행) | int -1 (+1행) | '*NULL*' NULL (+1행) | '*NULL*' NULL (+1행) |
| `date_plus` | '*NULL*' NULL (+1행) | date 01/02/2024 (+1행) | ERR:coerce | date 01/02/2024 (+1행) | ERR:overflow | date 01/03/2024 (+1행) | date 01/03/2024 (+1행) | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `datetime_minus` | '*NULL*' NULL (+1행) | ERR:coerce | bigint -82738889 (+1행) | dtt 01:01:01.110 AM 01/01/ (+1행) | ERR:Time_arithmetic_underflow | dtt 01:01:01.109 AM 01/01/ (+1행) | dtt 01:01:01.109 AM 01/01/ (+1행) | bigint -82738889 (+1행) | '*NULL*' NULL (+1행) | bigint -118740389 (+1행) |
| `enum_plus` | '*NULL*' NULL NULL (+1행) | varchar 'Yes1.0' '1.0Yes' (+1행) | varchar 'Yes2024-01-02' '2 (+1행) | varchar 2 2 (+1행) | varchar 9007199254740994 9 (+1행) | varchar 2.50 2.50 (+1행) | varchar 2.500000000000000e (+1행) | varchar 01/03/2024 01/03/2 (+1행) | varchar 10:00:02 AM 10:00: (+1행) | varchar 10:00:01.501 AM 01 (+1행) |
| `enum_minus` | '*NULL*' NULL NULL (+1행) | dbl 0.000000000000000e+00  (+1행) | ERR:coerce | int 0 0 (+1행) | bigint -9007199254740992 9 (+1행) | numeric -0.50 0.50 (+1행) | dbl -5.000000000000000e-01 (+1행) | ERR:Date_arithmetic_underflow | time 02:00:00 PM 10:00:00  (+1행) | bigint -212570992801499 10 (+1행) |
| `enum_eq` | 0 | 0 | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 |
| `enum_ne` | 0 | 3 | 3 | 2 | 3 | 2 | 2 | 3 | 3 | 3 |
| `enum_lt` | 0 | 0 | 0 | 0 | 3 | 1 | 1 | ERR:coerce | ERR:coerce | ERR:coerce |
| `enum_in` | 1 | 1 | 1 | 2 | 1 | 2 | 2 | 1 | 1 | 1 |
| `enum_insert` | NULL | ∅ ; ERR:coerce | ∅ ; ERR:coerce | 'Yes' | ∅ ; ERR:coerce | 'Yes' | 'Yes' | ∅ ; ERR:coerce | ∅ ; ERR:coerce | ∅ ; ERR:coerce |
| `set_plus` | NULL | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced | ERR:Invalid_data_type_referenced |
| `set_member_in` | 0 | 1 | · | 1 | 0 | 0 | 0 | · | · | · |

#### MR

| 문맥 \ bind | null | string | strdate | int | bigint | numeric | double | date | time | datetime |
|---|---|---|---|---|---|---|---|---|---|---|
| `values2` | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce |
| `values2_int` | dbl 1.000000000000000e+00 (+1행) | dbl 1.000000000000000e+00 (+1행) | · | dbl 1.000000000000000e+00 (+1행) | dbl 1.000000000000000e+00 (+1행) | dbl 1.000000000000000e+00 (+1행) | dbl 1.000000000000000e+00 (+1행) | · | · | · |
| `values_first` | '*NULL*' NULL (+1행) | dbl 1.000000000000000e+00 (+1행) | · | dbl 1.000000000000000e+00 (+1행) | dbl 9.007199254740992e+15 (+1행) | dbl 1.500000000000000e+00 (+1행) | dbl 1.500000000000000e+00 (+1행) | · | · | · |
| `values_both` | '*NULL*' NULL (+1행) ; NULL ; '1.0' ; '2024-01-02' | varchar '1.0' (+1행) | varchar '2024-01-02' (+1행) | int 1 (+1행) | bigint 9007199254740993 (+1행) | num(10,2) 1.50 (+1행) | dbl 1.500000000000000e+00 (+1행) | date 01/02/2024 (+1행) | time 10:00:01 AM (+1행) | dtt 10:00:01.500 AM 01/02/ (+1행) |
| `insert_values2` | 12:00:00.000 AM 01/01/2024 (+1행) ; '10:00:01' ; 1 ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | ∅ | 12:00:00.000 AM 01/01/2024 (+1행) | ∅ | ∅ | ∅ | ∅ | 12:00:00.000 AM 01/01/2024 (+1행) | ∅ | 12:00:00.000 AM 01/01/2024 (+1행) |
| `union_col_hv` | dbl 1.000000000000000e+00 (+2행) ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | dbl 1.000000000000000e+00 (+2행) | · | dbl 1.000000000000000e+00 (+2행) | dbl 1.000000000000000e+00 (+2행) | dbl 1.000000000000000e+00 (+2행) | dbl 1.000000000000000e+00 (+2행) | · | · | · |
| `union_hv_hv` | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | varchar '1.0' (+1행) | varchar '2024-01-02' (+1행) | int 1 (+1행) | bigint 9007199254740993 (+1행) | num(10,2) 1.50 (+1행) | dbl 1.500000000000000e+00 (+1행) | date 01/02/2024 (+1행) | time 10:00:01 AM (+1행) | dtt 10:00:01.500 AM 01/02/ (+1행) |
| `union_distinct` | NULL (+1행) | 1.000000000000000e+00 | · | 1.000000000000000e+00 | 1.000000000000000e+00 (+1행) | 1.000000000000000e+00 (+1행) | 1.000000000000000e+00 (+1행) | · | · | · |
| `insert_select` | NULL | 1 | ∅ ; ERR:coerce | 1 | ∅ ; ERR:overflow | 2 | 2 | ∅ ; ERR:coerce | ∅ ; ERR:coerce | ∅ ; ERR:coerce |
| `insert_select_expr` | NULL NULL (+1행) | 2 '1.0' (+1행) | ∅ ; ERR:coerce | 2 '1' (+1행) | ∅ ; ERR:overflow | 3 '1.50' (+1행) | 3 '1.5' (+1행) | ∅ ; ERR:coerce | ∅ ; ERR:coerce | ∅ ; ERR:coerce |
| `merge` | NULL | 1 | ∅ ; ERR:coerce | 1 | ∅ ; ERR:overflow | 2 | 2 | ∅ ; ERR:coerce | ∅ ; ERR:coerce | ∅ ; ERR:coerce |
| `merge_expr` | NULL NULL (+1행) | 2 '2' (+1행) | ∅ ; ERR:coerce | 2 '2' (+1행) | ∅ ; ERR:overflow | 3 '2.50' (+1행) | 3 '2.5' (+1행) | ∅ ; ERR:coerce | ∅ ; ERR:coerce | ∅ ; ERR:coerce |
| `derived_slot_cmp` | ∅ | '1.0' | ERR:coerce | 1 | ∅ | ∅ | ∅ | ERR:coerce | ∅ | ERR:coerce |
| `derived_slot_typeof` | '*NULL*' NULL ; NULL | varchar '1.0' | varchar '2024-01-02' | int 1 | bigint 9007199254740993 | num(10,2) 1.50 | dbl 1.500000000000000e+00 | date 01/02/2024 | time 10:00:01 AM | dtt 10:00:01.500 AM 01/02/ |
| `scalar_subq` | NULL ; '1.0' ; '2024-01-02' ; '10:00:01' ; 1 | 2.000000000000000e+00 | ERR:coerce | 2 | 9007199254740994 | 2.50 | 2.500000000000000e+00 | 01/03/2024 | 10:00:02 AM | 10:00:01.501 AM 01/02/2024 |
| `in_subq` | 0 ; 1 ; 9007199254740993 ; 1.50 ; 1.500000e+00 | 1 | · | 1 | 0 | 0 | 0 | · | · | · |
| `cte` | '*NULL*' NULL ; 1.500000000000000e+00 ; $1.50 ; 01/02/2024 ; 10:00:01 AM | varchar 2.000000000000000e | ERR:coerce | int 2 | bigint 9007199254740994 | num(10,2) 2.50 | dbl 2.500000000000000e+00 | date 01/03/2024 | time 10:00:02 AM | dtt 10:00:01.501 AM 01/02/ |
| `recursive_cte` | 10:00:01 AM 01/02/2024 ; 10:00:01.500 AM 01/02/2024 ; X'8' ; {1, 2} | ERR:incompat | ERR:coerce | int 1 (+2행) | bigint 9007199254740993 | ERR:incompat | dbl 1.500000000000000e+00 (+2행) | ERR:coerce | time 10:00:01 AM | ERR:coerce |
| `connect_by` | 1 NULL (+1행) | 1 '1.0' (+1행) | 1 '2024-01-02' (+1행) | 1 1 (+1행) | 1 9007199254740993 (+1행) | 1 1.50 (+1행) | 1 1.500000000000000e+00 (+1행) | 1 01/02/2024 (+1행) | 1 10:00:01 AM (+1행) | 1 10:00:01.500 AM 01/02/20 (+1행) |

#### SV2

| 문맥 \ bind | null | string | strdate | strtime | short | int | bigint | numeric | float | double | monetary | date | time | timestamp | datetime | bit |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `set` | '*NULL*' NULL | varchar '1.0' | varchar '2024-01-02' | varchar '10:00:01' | short 1 | int 1 | bigint 9007199254740993 | num(10,2) 1.50 | float 1.500000e+00 | dbl 1.500000000000000e+00 | monetary $1.50 | varchar '01/02/2024' | varchar '10:00:01 AM' | varchar '10:00:01 AM 01/02 | varchar '10:00:01.500 AM 0 | varchar '8' |
| `plus` | '*NULL*' NULL NULL | dbl 2.000000000000000e+00  | ERR:coerce | ERR:coerce | int 2 2 | int 2 2 | bigint 9007199254740994 18 | numeric 2.50 3.00 | float 2.500000e+00 3.00000 | dbl 2.500000000000000e+00  | monetary $2.50 $3.00 | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | dbl 9.000000000000000e+00  |
| `cmp` | NULL NULL 0 | 1 1 1 | ERR:coerce | ERR:coerce | 1 0 1 | 1 0 1 | 0 0 0 | 0 0 0 | 0 0 0 | 0 0 0 | 0 0 0 | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | 0 0 0 |
| `idx` | 0 | 1 | ERR:coerce | ERR:coerce | 1 | 1 | 0 | 0 | 0 | 0 | 0 | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | 0 |
| `to_char` | NULL NULL | '1.0' '1.0' | '2024-01-02' '2024-01-02' | '10:00:01' '10:00:01' | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | ERR:Invalid_format | '01/02/2024' '01/02/2024' | '10:00:01 AM' '10:00:01 AM | '10:00:01 AM 01/02/2024' ' | '10:00:01.500 AM 01/02/202 | '8' '8' |
| `addtime` | NULL | '01:00:01 AM' | '01:00:00.000 AM 01/02/202 | '11:00:01 AM' | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | ERR:Invalid_data_type_The_argume | '01:00:00.000 AM 01/02/202 | '11:00:01 AM' | '11:00:01.000 AM 01/02/202 | '11:00:01.500 AM 01/02/202 | '01:00:08 AM' |
| `lpad` | NULL | 'a 1.0' | 'a2024-' | 'a10:00' | 'a 1' | 'a 1' | 'a90071' | 'a 1.50' | 'a 1.5' | 'a 1.5' | 'a $1.5' | 'a01/02' | 'a10:00' | 'a10:00' | 'a10:00' | 'a 8' |
| `sum` | '*NULL*' NULL | dbl 5.000000000000000e+00 | ERR:coerce | ERR:coerce | short 5 | int 5 | bigint 45035996273704965 | num(10,2) 7.50 | float 7.500000e+00 | dbl 7.500000000000000e+00 | monetary $7.50 | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | dbl 4.000000000000000e+01 |
| `assign_expr` | NULL (+1행) ; '*NULL*' NULL | 2.000000000000000e+00 (+1행) ; dbl 3.000000000000000e+00 | dbl 3.000000000000000e+00 ; ERR:coerce | dbl 3.000000000000000e+00 ; ERR:coerce | 2 (+1행) ; int 3 | 2 (+1행) ; int 3 | 9007199254740994 (+1행) ; bigint 9007199254740995 | 2.50 (+1행) ; numeric 3.50 | 2.500000e+00 (+1행) ; float 3.500000e+00 | 2.500000000000000e+00 (+1행) ; dbl 3.500000000000000e+00 | $2.50 (+1행) ; monetary $3.50 | monetary $3.50 ; ERR:coerce | monetary $3.50 ; ERR:coerce | monetary $3.50 ; ERR:coerce | monetary $3.50 ; ERR:coerce | 9.000000000000000e+00 (+1행) ; dbl 1.000000000000000e+01 |
| `define_hv_p` | NULL '*NULL*' | '1.0' 'character varying ( | '2024-01-02' 'character va | '10:00:01' 'character vary | 1 'smallint' | 1 'integer' | 9007199254740993 'bigint' | 1.50 'numeric (10, 2)' | 1.500000e+00 'float' | 1.500000000000000e+00 'dou | $1.50 'monetary' | 01/02/2024 'date' | 10:00:01 AM 'time' | 10:00:01 AM 01/02/2024 'ti | 10:00:01.500 AM 01/02/2024 | X'8' 'bit (-1)' |
| `in_prepare_p` | NULL '*NULL*' | 2.000000000000000e+00 'dou | ERR:coerce | ERR:coerce | 2 'integer' | 2 'integer' | 9007199254740994 'bigint' | 2.50 'numeric' | 2.500000e+00 'float' | 2.500000000000000e+00 'dou | $2.50 'monetary' | ERR:coerce | ERR:coerce | ERR:coerce | ERR:coerce | 9.000000000000000e+00 'dou ; ERR:In_line__column__before__exi ; ERR:In_line__column__before__exi ; ERR:In_line__column__before__exi ; ERR:In_line__column__before__exi ; ERR:Precision_cannot_be_specifie |

#### PL

| 문맥 \ bind | null | date |
|---|---|---|
| `int` | ERR:Stored_procedure_execute_err | · |
| `str` | ERR:Stored_procedure_execute_err | ERR:Stored_procedure_execute_err |

#### 기타 (AGG.col, PL, COLL, MISC 등)

- `AGG.col.sum.i`: ERR:overflow
- `AGG.col.sum.b`: bigint 9007199254740999
- `AGG.col.sum.n`: numeric 11.00
- `AGG.col.sum.d`: dbl 1.200000000000000e+01
- `AGG.col.sum.s`: ERR:coerce
- `AGG.col.sum.sd`: ERR:coerce
- `AGG.col.sum.dt`: ERR:coerce ; ERR:coerce
- `AGG.col.sum.dtt`: ERR:coerce ; ERR:coerce
- `AGG.col.sum.e`: int 6
- `AGG.col.avg.i`: ERR:overflow
- `AGG.col.avg.b`: dbl 2.251799813685250e+15
- `AGG.col.avg.n`: dbl 2.750000000000000e+00
- `AGG.col.avg.d`: dbl 3.000000000000000e+00
- `AGG.col.avg.s`: ERR:coerce
- `AGG.col.avg.sd`: ERR:coerce
- `AGG.col.avg.dt`: ERR:coerce ; ERR:coerce
- `AGG.col.avg.dtt`: ERR:coerce ; ERR:coerce
- `AGG.col.avg.e`: dbl 2.000000000000000e+00
- `AGG.col.min.i`: int 1
- `AGG.col.min.b`: bigint 1
- `AGG.col.min.n`: num(10,2) 1.10
- `AGG.col.min.d`: dbl 1.500000000000000e+00
- `AGG.col.min.s`: varchar '1'
- `AGG.col.min.sd`: varchar '2024-01-01'
- `AGG.col.min.dt`: date 01/01/2024
- `AGG.col.min.dtt`: dtt 01:01:01.111 AM 01/01/
- `AGG.col.min.e`: 'enum' 'Yes'
- `AGG.col.max.i`: int 2147483647
- `AGG.col.max.b`: bigint 9007199254740993
- `AGG.col.max.n`: num(10,2) 4.40
- `AGG.col.max.d`: dbl 4.500000000000000e+00
- `AGG.col.max.s`: varchar 'x'
- `AGG.col.max.sd`: varchar 'notadate'
- `AGG.col.max.dt`: date 01/03/2024
- `AGG.col.max.dtt`: dtt 03:03:03.333 AM 01/03/
- `AGG.col.max.e`: 'enum' 'Cancel'
- `AGG.col.count.i`: bigint 4
- `AGG.col.count.b`: bigint 4
- `AGG.col.count.n`: bigint 4
- `AGG.col.count.d`: bigint 4
- `AGG.col.count.s`: bigint 4
- `AGG.col.count.sd`: bigint 4
- `AGG.col.count.dt`: bigint 3
- `AGG.col.count.dtt`: bigint 3
- `AGG.col.count.e`: bigint 3
- `AGG.col.median.i`: dbl 2.500000000000000e+00
- `AGG.col.median.b`: dbl 2.500000000000000e+00
- `AGG.col.median.n`: dbl 2.750000000000000e+00
- `AGG.col.median.d`: dbl 3.000000000000000e+00
- `AGG.col.median.s`: ERR:coerce
- `AGG.col.median.sd`: ERR:coerce
- `AGG.col.median.dt`: date 01/02/2024
- `AGG.col.median.dtt`: dtt 02:02:02.222 AM 01/02/
- `AGG.col.median.e`: ERR:incompat ; ERR:incompat
- `AGG.col.stddev.i`: dbl 9.298876953908015e+08
- `AGG.col.stddev.b`: dbl 3.900231685776980e+15
- `AGG.col.stddev.n`: dbl 1.229837387624884e+00
- `AGG.col.stddev.d`: dbl 1.118033988749895e+00
- `AGG.col.stddev.s`: ERR:coerce
- `AGG.col.stddev.sd`: ERR:coerce
- `AGG.col.stddev.dt`: ERR:incompat ; ERR:before___stddevdt_from_tg
- `AGG.col.stddev.dtt`: ERR:incompat ; ERR:before___stddevdtt_from_tg
- `AGG.col.stddev.e`: dbl 8.164965809277263e-01
- `AGG.col.variance.i`: dbl 8.646911260392161e+17
- `AGG.col.variance.b`: dbl 1.521180720273875e+31
- `AGG.col.variance.n`: dbl 1.512499999999999e+00
- `AGG.col.variance.d`: dbl 1.250000000000000e+00
- `AGG.col.variance.s`: ERR:coerce
- `AGG.col.variance.sd`: ERR:coerce
- `AGG.col.variance.dt`: ERR:incompat ; ERR:before___variancedt_from_tg
- `AGG.col.variance.dtt`: ERR:incompat ; ERR:before___variancedtt_from_tg
- `AGG.col.variance.e`: dbl 6.666666666666670e-01
- `AGG.col.group_concat.i`: varchar '1,2,3,2147483647'
- `AGG.col.group_concat.b`: varchar '1,2,3,90071992547
- `AGG.col.group_concat.n`: varchar '1.10,2.20,3.30,4.
- `AGG.col.group_concat.d`: varchar '1.5,2.5,3.5,4.5'
- `AGG.col.group_concat.s`: varchar '1,2,3,x'
- `AGG.col.group_concat.sd`: varchar '2024-01-01,2024-0
- `AGG.col.group_concat.dt`: varchar '01/01/2024,01/02/
- `AGG.col.group_concat.dtt`: varchar '01:01:01.111 AM 0
- `AGG.col.group_concat.e`: varchar 'Yes,No,Cancel'
- `AGG.sum_int_overflow`: ERR:overflow
- `AGG.sum_int_group`: ERR:overflow
- `AGG.percentile_cont_col`: dbl 2.750000000000000e+00
- `AGG.percentile_cont_varchar`: 1.200000000000000e+00
- `AGG.percentile_cont_varchar_date`: 04:48:00.000 AM 01/01/2024
- `AGG.percentile_disc_varchar`: 1.000000000000000e+00
- `AGG.median_varchar_num`: 1.500000000000000e+00
- `AGG.median_varchar_date`: 12:00:00.000 PM 01/01/2024
- `AGG.median_varchar_mixed`: ERR:coerce
- `AGG.median_over`: ERR:coerce
- `AGG.union_mixed_sum`: ERR:incompat
- `AGG.union_mixed_sum2`: ERR:incompat
- `PL.int.1`: ERR:Stored_procedure_execute_err
- `PL.num.1234568`: ERR:before_____Methods_require_a
- `PL.num.0_40`: ERR:before_____Methods_require_a
- `PL.str.b`: ERR:Stored_procedure_execute_err
- `COLL.baseline`: 'utf8_bin' 10 'utf8'
- `COLL.hv_collation`: 'utf8_bin' 11 'utf8'
- `COLL.concat_hv_hv`: 'ab' 'utf8_bin'
- `COLL.eq_hv_hv_case`: 0
- `COLL.eq_col_hv`: 1
- `COLL.col_ci_hv`: 2
- `COLL.col_cs_hv`: 1
- `COLL.nullif_col_hv`: NULL NULL (+1행)
- `COLL.coalesce_hv_col`: 'A' 'utf8_en_cs' (+1행)
- `COLL.case_hv_col`: 'A' 'utf8_en_cs' (+1행)
- `COLL.between_hv`: 2
- `COLL.like_hv`: 2
- `COLL.in_hv`: 2
- `COLL.after_set_names`: 'utf8_en_ci' 8
- `COLL.hv_after_set_names`: 'utf8_en_ci' 'utf8_en_ci' 
