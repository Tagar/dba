
SELECT * FROM 
(   SELECT target_name,
           CASE WHEN metric_column IN ('ofs_free_gb','ofs_size_gb') THEN key_value2 ELSE key_value END diskgroup,
           metric_column metric,
           CASE WHEN metric_column LIKE '%_mb'      THEN TO_CHAR(TO_NUMBER(VALUE)/1024,'999999.99')    -- Mb to Gb
                WHEN metric_column LIKE '%_gb'      THEN TO_CHAR(TO_NUMBER(VALUE)     ,'999999.99')    -- Gb
                WHEN metric_column LIKE 'percent_%' THEN TO_CHAR(ROUND(TO_NUMBER(VALUE),1))       -- 1 decimal digit
                ELSE VALUE
           END value
        FROM MGMT$METRIC_CURRENT
      WHERE target_type IN ('osm_cluster','osm_instance') 
        AND metric_column IN( 'type','usable_file_mb' ,'usable_total_mb' ,'percent_used' --,'free_mb'      
                          ,'diskCnt','rebalInProgress','resyncInProgress','computedImbalance'
                          ,'ofs_free_gb','ofs_size_gb'  -- ACFS
                          )
        AND key_value2<>'none' -- ACFS
)
PIVOT
(   MAX(value)
    FOR metric IN 
    (    'percent_used'      as "% Used"
       , 'usable_total_mb'   as "Total, Gb"
       , 'usable_file_mb'    as "Free, Gb"
       , 'ofs_size_gb'       as "ACFS Size, Gb"
       , 'ofs_free_gb'       as "ACFS Free, Gb"
       , 'diskCnt'           as "# disks"
       , 'type'              as "Redundancy"
       , 'rebalInProgress'   as "Rebalancing"
       , 'computedImbalance' as "Imbalance"         -- not documented
       , 'resyncInProgress'  as "Resyncing"
    )
)
ORDER BY target_name, diskgroup
;



------------------------ older version :
/*
SELECT * FROM 
(   SELECT target_name,
           key_value diskgroup,
           metric_column metric,
           CASE WHEN metric_column LIKE '%_mb'      THEN TO_CHAR(TO_NUMBER(VALUE)/1024,'999999.99')    -- Mb to Gb
                WHEN metric_column LIKE 'percent_%' THEN TO_CHAR(ROUND(TO_NUMBER(VALUE),1))       -- 1 decimal digit
                ELSE VALUE
           END value
        FROM MGMT$METRIC_CURRENT
      WHERE target_type IN ('osm_cluster','osm_instance') 
        AND metric_column IN( 'type','usable_file_mb' ,'usable_total_mb' ,'percent_used' --,'free_mb'      
                          ,'diskCnt','rebalInProgress','resyncInProgress','computedImbalance')
  UNION ALL -- separate query for ACFS:
    SELECT target_name,
           key_value2 diskgroup,
           metric_column metric,
           CASE WHEN metric_column LIKE '%_gb'      THEN TO_CHAR(TO_NUMBER(VALUE),'999999.99')
                ELSE VALUE
           END value
        FROM MGMT$METRIC_CURRENT
      WHERE target_type IN ('osm_cluster','osm_instance') 
        AND metric_column IN ('ofs_free_gb','ofs_size_gb')
        AND key_value2<>'none'
)
PIVOT
(   MAX(value)
    FOR metric IN 
    (    'percent_used'      as "% Used"
       --, 'free_mb'           as "Free, Gb"        -- this is raw space (not very useful when redundancy <> 'EXTERNAL')
       , 'usable_total_mb'   as "Total, Gb"
       , 'usable_file_mb'    as "Free, Gb"
       --, 'total_mb'          as "Total, Gb"
       , 'ofs_size_gb'       as "ACFS Size, Gb"
       , 'ofs_free_gb'       as "ACFS Free, Gb"
       , 'diskCnt'           as "# disks"
       , 'type'              as "Redundancy"
       , 'rebalInProgress'   as "Rebalancing"
       , 'computedImbalance' as "Imbalance"         -- not documented
       , 'resyncInProgress'  as "Resyncing"
    )
)
ORDER BY CASE WHEN TO_NUMBER(TRIM("ACFS Size, Gb"))>0 
                   THEN TO_NUMBER(TRIM("ACFS Free, Gb"))/TO_NUMBER(TRIM("ACFS Size, Gb"))
                   ELSE TO_NUMBER(TRIM("Free, Gb"))/TO_NUMBER(TRIM("Total, Gb"))
         END
*/