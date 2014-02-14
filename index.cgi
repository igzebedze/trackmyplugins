#!/usr/bin/perl -w

use strict;

use CGI::Fast qw(:standard);
use JSON;
use DBI;
use POSIX;

my $dbh = DBI->connect(          
	    "dbi:SQLite:dbname=test.db", 
	    "",                          
	    "",                          
	    { RaiseError => 1 },         
	) or die $DBI::errstr;

# -- get the data --

# by default print html summary of last month or something
my $month = strftime '%m', localtime;
my $year = strftime '%Y', localtime;

# support queries: exact_date, exact_month
# support filters: match by field "Name"

# -- print the outputs ---

while (new CGI::Fast) {
	print header;
	print start_html("Fast CGI Rocks");
	print 
		h1("your downloads this month");

	my $sth = $dbh->prepare("SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$year-$month-%'");
	$sth->execute();

	my %downloads;
	while (my ($name, $date, $dlls) = $sth->fetchrow()) {
		#print "$name, $date, $dlls\n";
		$downloads{$name} += $dlls;
		$downloads{'total'} += $dlls;
	}

	print "<table><tr><td>plugin</td><td>downloads</td></tr>";
	foreach my $plugin(keys(%downloads)){
		print "<tr><td>$plugin</td><td>".$downloads{$plugin}."</td></tr>";
	}
	
	print "</table>";

	$sth->finish();
    print end_html;
}

$dbh->disconnect();

