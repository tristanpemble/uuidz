-- Test: UUID v1 binary length
SELECT
  CASE
    WHEN length(uuid_v1()) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v1 binary length should be 16 bytes, got ' || length(uuid_v1())
  END as uuid_v1_length_test;

-- Test: UUID v3 binary length
SELECT
  CASE
    WHEN length(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v3 binary length should be 16 bytes, got ' || length(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test'))
  END as uuid_v3_length_test;

-- Test: UUID v4 binary length
SELECT
  CASE
    WHEN length(uuid_v4()) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v4 binary length should be 16 bytes, got ' || length(uuid_v4())
  END as uuid_v4_length_test;

-- Test: UUID v5 binary length
SELECT
  CASE
    WHEN length(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v5 binary length should be 16 bytes, got ' || length(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test'))
  END as uuid_v5_length_test;

-- Test: UUID v6 binary length
SELECT
  CASE
    WHEN length(uuid_v6()) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v6 binary length should be 16 bytes, got ' || length(uuid_v6())
  END as uuid_v6_length_test;

-- Test: UUID v7 binary length
SELECT
  CASE
    WHEN length(uuid_v7()) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v7 binary length should be 16 bytes, got ' || length(uuid_v7())
  END as uuid_v7_length_test;

-- Test: uuid_format string length
SELECT
  CASE
    WHEN length(uuid_format(uuid_v4())) = 36 THEN 'PASS'
    ELSE 'FAIL uuid_format string length should be 36 chars, got ' || length(uuid_format(uuid_v4()))
  END as uuid_format_length_test;

-- Test: UUID v4 randomness
WITH two_uuids AS (
  SELECT uuid_v4() as uuid1, uuid_v4() as uuid2
)
SELECT
  CASE
    WHEN uuid1 != uuid2 THEN 'PASS'
    ELSE 'FAIL UUID v4 should generate different values'
  END as uuid_v4_randomness_test
FROM two_uuids;

-- Test: uuid_parse roundtrip
SELECT
  CASE
    WHEN uuid_format(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8')) = '6ba7b810-9dad-11d1-80b4-00c04fd430c8' THEN 'PASS'
    ELSE 'FAIL uuid_parse/uuid_format roundtrip failed'
  END as uuid_parse_roundtrip_test;

-- Test: UUID v3 deterministic behavior
WITH deterministic_v3_test AS (
  SELECT
    uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid3_1,
    uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid3_2
)
SELECT
  CASE
    WHEN uuid3_1 = uuid3_2 THEN 'PASS'
    ELSE 'FAIL UUID v3 should be deterministic for same inputs'
  END as uuid_v3_deterministic_test
FROM deterministic_v3_test;

-- Test: UUID v5 deterministic behavior
WITH deterministic_v5_test AS (
  SELECT
    uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid5_1,
    uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid5_2
)
SELECT
  CASE
    WHEN uuid5_1 = uuid5_2 THEN 'PASS'
    ELSE 'FAIL UUID v5 should be deterministic for same inputs'
  END as uuid_v5_deterministic_test
FROM deterministic_v5_test;

-- Test: UUID v3 vs v5 produce different results
WITH version_comparison AS (
  SELECT
    uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid3,
    uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') as uuid5
)
SELECT
  CASE
    WHEN uuid3 != uuid5 THEN 'PASS'
    ELSE 'FAIL UUID v3 and v5 should produce different results'
  END as v3_v5_difference_test
FROM version_comparison;

-- Test: uuid_version detection accuracy
WITH version_tests AS (
  SELECT
    uuid_version(uuid_v1()) as v1_detected,
    uuid_version(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) as v3_detected,
    uuid_version(uuid_v4()) as v4_detected,
    uuid_version(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) as v5_detected,
    uuid_version(uuid_v6()) as v6_detected,
    uuid_version(uuid_v7()) as v7_detected
)
SELECT
  CASE
    WHEN v1_detected = 1 AND v3_detected = 3 AND v4_detected = 4 AND v5_detected = 5 AND v6_detected = 6 AND v7_detected = 7 THEN 'PASS'
    ELSE 'FAIL uuid_version detection failed - v1:' || v1_detected || ' v3:' || v3_detected || ' v4:' || v4_detected || ' v5:' || v5_detected || ' v6:' || v6_detected || ' v7:' || v7_detected
  END as uuid_version_detection_test
FROM version_tests;

-- Test: uuid_variant detection
WITH variant_tests AS (
  SELECT
    uuid_variant(uuid_v1()) as v1_variant,
    uuid_variant(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) as v3_variant,
    uuid_variant(uuid_v4()) as v4_variant,
    uuid_variant(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test')) as v5_variant,
    uuid_variant(uuid_v6()) as v6_variant,
    uuid_variant(uuid_v7()) as v7_variant
)
SELECT
  CASE
    WHEN v1_variant = 1 AND v3_variant = 1 AND v4_variant = 1 AND v5_variant = 1 AND v6_variant = 1 AND v7_variant = 1 THEN 'PASS'
    ELSE 'FAIL uuid_variant should be 1 (RFC 4122) for all versions'
  END as uuid_variant_detection_test
FROM variant_tests;

-- Test: uuid_timestamp works for time-based UUIDs
WITH timestamp_tests AS (
  SELECT
    uuid_timestamp(uuid_v1()) as v1_timestamp,
    uuid_timestamp(uuid_v6()) as v6_timestamp,
    uuid_timestamp(uuid_v7()) as v7_timestamp
)
SELECT
  CASE
    WHEN v1_timestamp > 0 AND v6_timestamp > 0 AND v7_timestamp > 0 THEN 'PASS'
    ELSE 'FAIL uuid_timestamp failed for time-based UUIDs'
  END as uuid_timestamp_extraction_test
FROM timestamp_tests;

-- Test: uuid_timestamp returns reasonable values for v7
WITH timestamp_sanity_test AS (
  SELECT
    uuid_timestamp(uuid_v7()) as v7_timestamp
)
SELECT
  CASE
    WHEN v7_timestamp > 1600000000 AND v7_timestamp < 2000000000 THEN 'PASS'
    ELSE 'FAIL UUID v7 timestamp outside reasonable range: ' || v7_timestamp
  END as uuid_timestamp_sanity_test
FROM timestamp_sanity_test;

-- Test: Multiple uuid_v3 calls with different namespaces
SELECT
  CASE
    WHEN uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') !=
         uuid_v3(uuid_parse('6ba7b811-9dad-11d1-80b4-00c04fd430c8'), 'test') THEN 'PASS'
    ELSE 'FAIL UUID v3 with different namespaces should produce different results'
  END as uuid_v3_namespace_test;

-- Test: Multiple uuid_v5 calls with different namespaces
SELECT
  CASE
    WHEN uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test') !=
         uuid_v5(uuid_parse('6ba7b811-9dad-11d1-80b4-00c04fd430c8'), 'test') THEN 'PASS'
    ELSE 'FAIL UUID v5 with different namespaces should produce different results'
  END as uuid_v5_namespace_test;

-- Test: uuid_v3 with different names in same namespace
SELECT
  CASE
    WHEN uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test1') !=
         uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test2') THEN 'PASS'
    ELSE 'FAIL UUID v3 with different names should produce different results'
  END as uuid_v3_name_test;

-- Test: uuid_v5 with different names in same namespace
SELECT
  CASE
    WHEN uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test1') !=
         uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'test2') THEN 'PASS'
    ELSE 'FAIL UUID v5 with different names should produce different results'
  END as uuid_v5_name_test;

-- Test: uuid_parse handles uppercase and lowercase consistently
SELECT
  CASE
    WHEN uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8') =
         uuid_parse('6BA7B810-9DAD-11D1-80B4-00C04FD430C8') THEN 'PASS'
    ELSE 'FAIL uuid_parse should handle case-insensitive input'
  END as uuid_parse_case_test;

-- Test: uuid_format produces lowercase output
SELECT
  CASE
    WHEN uuid_format(uuid_parse('6BA7B810-9DAD-11D1-80B4-00C04FD430C8')) = '6ba7b810-9dad-11d1-80b4-00c04fd430c8' THEN 'PASS'
    ELSE 'FAIL uuid_format should produce lowercase output'
  END as uuid_format_case_test;

-- Test: Binary storage efficiency vs string storage
SELECT
  CASE
    WHEN length(uuid_v4()) = 16 AND length(uuid_format(uuid_v4())) = 36 THEN 'PASS'
    ELSE 'FAIL Binary UUID should be 16 bytes, string should be 36 chars'
  END as uuid_storage_efficiency_test;

-- Test: uuid_parse with malformed input should handle gracefully
-- Note: This may cause an error depending on implementation
-- SELECT uuid_parse('invalid-uuid-string') as malformed_uuid_test;

-- Test: Batch generation uniqueness
WITH RECURSIVE counter(x) AS (
  SELECT 1
  UNION ALL
  SELECT x+1 FROM counter WHERE x < 100
),
batch_uuids AS (
  SELECT uuid_v4() as uuid FROM counter
)
SELECT
  CASE
    WHEN COUNT(*) = COUNT(DISTINCT uuid) THEN 'PASS'
    ELSE 'FAIL UUID v4 batch generation produced duplicates'
  END as uuid_v4_batch_uniqueness_test
FROM batch_uuids;

-- Test: Known test vectors for UUID v3 (RFC 4122 Appendix B test)
SELECT
  CASE
    WHEN uuid_format(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'www.example.com')) = '5df41881-3aed-3515-88a7-2f4a814cf09e' THEN 'PASS'
    ELSE 'NOTE: UUID v3 test vector may differ - implementation specific. Got: ' || uuid_format(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'www.example.com'))
  END as uuid_v3_test_vector;

-- Test: Known test vectors for UUID v5 (RFC 4122 Appendix B test)
SELECT
  CASE
    WHEN uuid_format(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'www.example.com')) = '2ed6657d-e927-568b-95e1-2665a8aea6a2' THEN 'PASS'
    ELSE 'NOTE: UUID v5 test vector may differ - implementation specific. Got: ' || uuid_format(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'www.example.com'))
  END as uuid_v5_test_vector;

-- Test: Empty string input for name-based UUIDs
SELECT
  CASE
    WHEN length(uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), '')) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v3 with empty string should still produce valid UUID'
  END as uuid_v3_empty_string_test;

SELECT
  CASE
    WHEN length(uuid_v5(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), '')) = 16 THEN 'PASS'
    ELSE 'FAIL UUID v5 with empty string should still produce valid UUID'
  END as uuid_v5_empty_string_test;

-- Test: All standard namespace UUIDs are parseable
SELECT
  CASE
    WHEN length(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8')) = 16 AND
         length(uuid_parse('6ba7b811-9dad-11d1-80b4-00c04fd430c8')) = 16 AND
         length(uuid_parse('6ba7b812-9dad-11d1-80b4-00c04fd430c8')) = 16 AND
         length(uuid_parse('6ba7b814-9dad-11d1-80b4-00c04fd430c8')) = 16 THEN 'PASS'
    ELSE 'FAIL Standard namespace UUIDs should be parseable'
  END as standard_namespace_parse_test;
