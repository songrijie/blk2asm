# blk2asm

Introduction
=============
Show the mapping between oracle blocks/table and ASM disks/failure group.  
This is especially useful to find in which Exadata cell one particular block resides on. 

Requirements
============
This script is supposed to be executed with "grid" user environment in Oracle 11.2 and 12.1. 
blk2asm.sh checkes the enviornment before calling blk2asm.pl.
"perl" installed under "GRID HOME" is used as interpreter. 

Connections
===========
The script connects to ASM and DB instance with DBD. 
It creates parameter files to save the DB connection information without enciphering the password.  

Features
========
For now, 4 forms of inputs are accepted: 'rowid', or 'fileID,blockID', or 'schema.tableName', or 'tableName'

1. 'rowid', or 'fileID,blockID'

The information of this particular block is showed, including ASM disks, failgroup and etc. 

2. 'schema.tableName', or 'tableName'

The aggregated information of this particular table. Refer to sample_table.out


Execution
=========
./blk2asm

-- follow the interaction steps. 


Planning
========
Include block check other than db blocks. 

Control file,
File check
