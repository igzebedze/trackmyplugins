trackmyplugins
==============

script that connects to several api's to collect download data

the problem: tracking downloads of your plugins from several sources:
 - wordpress plugins
 - firefox extensions
 - chrome extensions
 - custom downloads tracked by bit.ly

the solution: 
 - simple perl script with all four scrapers, utilizing Mechanize library
 - configure the list of plugins from simple text file
 - configure your secrets from simple text file (keep it safe!)
 - sqlite3 database with dates and #downloads for each plugin
 - simple flask script that serves the data via json API

see it live at XXX