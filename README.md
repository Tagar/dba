DBA scripts
===========

various scripts for an Oracle DBA

check_oratabs.pl - checks (and updates) oratab files in a cluster, according to settings in clusterware.

orion/orion_3d_plot.r - plots 3D graphs for ORION IO test results.

sas/sas2oraextab.pl - SAS to Oracle external table DDLs generator. Comes up with column names based on 
  description, creates multiple tables if there are more than 1000 columns in source SAS file.

check_multipath.pl - runs iostat for each multipath device group and prints disbalance.
  If multipath wouldn’t be used, devices wouldn’t be used equally for reads or for writes.
  Had a problem when some oracleasm devices in /dev/oracleasm/disks/ were pointing to sd and not dm devices.
  check_multipath.pl script detects such problems.
