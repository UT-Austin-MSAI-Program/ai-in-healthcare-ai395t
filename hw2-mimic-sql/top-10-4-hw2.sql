-- CREATE OR REPLACE TABLE `mimic_helpers.filtered_patients` AS
-- SELECT 
--     subject_id, 
--     dob, 
--     dod,
--     gender,
--     DATE_DIFF(COALESCE(dod, CURRENT_DATE()), dob, YEAR) AS age
-- FROM `physionet-data.mimiciii_clinical.patients`
-- WHERE DATE_DIFF(COALESCE(dod, CURRENT_DATE()), dob, YEAR) < 120;

-- SELECT * FROM `mimic_helpers.filtered_patients`
-- ORDER BY age DESC;

-- 1 Retrieve patient demographics along with their first recorded microbiology test result.
WITH first_microbio AS (
    SELECT 
        m.subject_id, 
        m.charttime, 
        m.spec_type_desc, 
        m.org_name,
        p.gender, 
        p.age,
        ROW_NUMBER() OVER (PARTITION BY m.subject_id ORDER BY m.charttime ASC) AS rn
    FROM `physionet-data.mimiciii_clinical.microbiologyevents` m
    JOIN `physionet-data.mimiciii_clinical.admissions` a 
        ON m.subject_id = a.subject_id
    JOIN `learned-alcove-449419-s2.mimic_helpers.filtered_patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.age > -1 AND m.charttime IS NOT NULL
    AND m.org_name IS NOT NULL
)
SELECT subject_id, gender, age, charttime, spec_type_desc, org_name
FROM first_microbio
WHERE rn = 1
ORDER BY charttime ASC;

-- 2 Find the most common organism cultured from blood samples.
SELECT org_name, COUNT(*) AS occurrence_count
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE LOWER(spec_type_desc) LIKE'%blood%' AND org_name IS NOT NULL
GROUP BY org_name
ORDER BY occurrence_count DESC
LIMIT 10;

-- 3 Identify patients who tested positive for a specific pathogen more than once.
SELECT subject_id, org_name, COUNT(*) AS positive_count
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE interpretation = 'R'
AND subject_id IN (
    SELECT subject_id 
    FROM `physionet-data.mimiciii_clinical.microbiologyevents`
    WHERE interpretation = 'R'
    GROUP BY subject_id, org_name
    HAVING COUNT(*) > 1
)
GROUP BY subject_id, org_name;

-- 4 Analyze trends in antibiotic resistance over time.
SELECT EXTRACT(YEAR FROM charttime) AS year, org_name, ab_name, interpretation, COUNT(*) AS resistance_count
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE interpretation = 'R'
AND EXTRACT(YEAR FROM charttime) IS NOT NULL
GROUP BY year, org_name, ab_name, interpretation
ORDER BY resistance_count DESC;

--5 List the most resistant bacterial strains based on susceptibility test results.
SELECT org_name, ab_name, COUNT(*) AS resistant_cases
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE interpretation = 'R'
GROUP BY org_name, ab_name
ORDER BY resistant_cases DESC
LIMIT 10;

-- 6 Determine how many patients acquired infections after hospital admission.
SELECT m.subject_id, a.admittime, m.charttime, m.spec_type_desc, m.org_name,
       (m.charttime - a.admittime) AS time_to_infection
FROM `physionet-data.mimiciii_clinical.microbiologyevents` m
JOIN `physionet-data.mimiciii_clinical.admissions` a ON m.subject_id = a.subject_id
WHERE (m.charttime - a.admittime) > INTERVAL 48 HOUR AND m.org_name IS NOT NULL
ORDER BY time_to_infection ASC;

-- 7 Find the most common infections among ICU patients.
SELECT m.org_name, COUNT(*) AS infection_count
FROM `physionet-data.mimiciii_clinical.microbiologyevents` m
JOIN `physionet-data.mimiciii_clinical.admissions` a ON m.subject_id = a.subject_id
JOIN `physionet-data.mimiciii_clinical.icustays` icu ON a.subject_id = icu.subject_id
WHERE org_name IS NOT NULL
GROUP BY m.org_name
ORDER BY infection_count DESC
LIMIT 10;

-- 8 Compare common pathogens found in blood vs. urine cultures.
SELECT spec_type_desc, org_name, COUNT(*) AS occurrence
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE (`SPEC_TYPE_DESC` IN ('BLOOD CULTURE',
      'URINE'))
AND org_name IS NOT NULL
GROUP BY spec_type_desc, org_name
ORDER BY occurrence DESC
LIMIT 10;

-- 9 Identify whether specific infections are correlated with higher in-hospital mortality.
SELECT 
    m.org_name, 
    COUNT(DISTINCT m.subject_id) AS infected_patients, 
    COUNT(DISTINCT CASE WHEN a.hospital_expire_flag = 1 THEN a.subject_id END) AS deaths, 
    ROUND((COUNT(DISTINCT CASE WHEN a.hospital_expire_flag = 1 THEN a.subject_id END) * 100.0) / COUNT(DISTINCT m.subject_id), 2) AS mortality_rate
FROM `physionet-data.mimiciii_clinical.microbiologyevents` m
JOIN `physionet-data.mimiciii_clinical.admissions` a 
ON m.subject_id = a.subject_id
WHERE org_name IS NOT NULL
GROUP BY m.org_name
ORDER BY infected_patients DESC
LIMIT 10;

-- 10 Determine the time of year with the highest number of positive microbiology results.
SELECT EXTRACT(MONTH FROM charttime) AS month, COUNT(*) AS positive_cases
FROM `physionet-data.mimiciii_clinical.microbiologyevents`
WHERE interpretation IS NOT NULL AND EXTRACT(MONTH FROM charttime) IS NOT NULL
GROUP BY month
ORDER BY positive_cases DESC;
