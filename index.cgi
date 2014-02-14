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
my $day = strftime '%d', localtime;
my $year = strftime '%Y', localtime;

my $lastmonth = strftime '%m', localtime(time() - 30 * 24 * 60 * 60);
my $lastyear = strftime '%Y', localtime(time() - 30 * 24 * 60 * 60);


# support queries: exact_date, exact_month
# support filters: match by field "Name"

# -- print the outputs ---

while (new CGI::Fast) {
	print header;
	print start_html("Fast CGI Rocks");
	print 
		h1("your downloads");

# month to date
	my $sth = $dbh->prepare("SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$year-$month-%'");
	$sth->execute();

	my %downloads;
	while (my ($name, $date, $dlls) = $sth->fetchrow()) {
		#print "$name, $date, $dlls\n";
		$downloads{$name} += $dlls;
		$downloads{'total'} += $dlls;
	}

# previous month
	$sth = $dbh->prepare("SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$lastyear-$lastmonth-%'");
	$sth->execute();

	my %lastdownloads;
	while (my ($name, $date, $dlls) = $sth->fetchrow()) {
		#print "$name, $date, $dlls\n";
		$lastdownloads{$name} += $dlls;
		$lastdownloads{'total'} += $dlls;
	}

	print "<table border='1'><tr><th>plugin</th><th>last month</th><th>month to date</th><th>eom estimate</th></tr>";
	foreach my $plugin(keys(%downloads)){
		print "<tr><td>$plugin</td><td>".$lastdownloads{$plugin}."</td><td>".$downloads{$plugin}."</td><td>".int($downloads{$plugin} * 30 / $day)."</td></tr>";
	}
	
	print "</table>";

	$sth->finish();
    print end_html;
}

$dbh->disconnect();

