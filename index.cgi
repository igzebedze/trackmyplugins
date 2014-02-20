#!/usr/bin/perl -w

use strict;

use CGI::Fast qw(:standard);
use JSON;
use DBI;
use POSIX;

my $dbh = DBI->connect(          
	    "dbi:SQLite:dbname=data.db", 
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
	# http://ceo.io/zemanta/downloads/?daily=1&date=2013-04-03
	# http://ceo.io/zemanta/downloads/?date=2013-04

# support filters: match by field "Name"
	# http://ceo.io/zemanta/downloads/?daily=1&date=2013-04-03&filter=wpea
	# http://ceo.io/zemanta/downloads/?date=2012-03&filter=wpea

# -- print the outputs ---

while (my $q = new CGI::Fast) {
	print header;

	my $daily = $q->param('daily');
	my $chosendate = $q->param('date');
	my $filter = $q->param('filter');

	if ($daily) {
		if (!$chosendate) {	# default to yesterday
			my $yesterday = strftime '%d', localtime(time() - 24 * 60 * 60);
			my $yestermonth = strftime '%m', localtime(time() - 24 * 60 * 60);
			my $yesteryear = strftime '%Y', localtime(time() - 24 * 60 * 60);
			$chosendate = "$yesteryear-$yestermonth-$yesterday";
		}
		my $dbquery = "SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$chosendate'";
			$dbquery = $dbquery." AND Name = '$filter'" if $filter;

		my $sth = $dbh->prepare($dbquery);
			$sth->execute();
	
		my %downloads;
		my $count = 0;
		while (my ($name, $date, $dlls) = $sth->fetchrow()) {
			#print "$name, $date, $dlls\n";
			$downloads{$name} += $dlls;
			$downloads{'total'} += $dlls;
			$count++;
		}

		$downloads{'date'} = $chosendate;
		$downloads{'filter'} = $filter if $filter;

		my $json = JSON->new;
		my $pretty = $json->pretty->encode(\%downloads);
		print $pretty;
	} else {
		my $json = 0;
		if (!$chosendate) { 	# default to current month
			$chosendate = "$year-$month-%";
		} else {				# else print json
			$chosendate = $chosendate."-%";
			$json = 1;
		}
	
	# month to date
		my $dbquery = "SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$chosendate'";
			$dbquery = $dbquery." AND Name = '$filter'" if $filter;
		my $sth = $dbh->prepare($dbquery);
			$sth->execute();
	
		my %downloads;
		while (my ($name, $date, $dlls) = $sth->fetchrow()) {
			#print "$name, $date, $dlls\n";
			$downloads{$name} += $dlls;
			$downloads{'total'} += $dlls;
		}
	
		if ($json) {
			$downloads{'date'} = $chosendate;
			$downloads{'filter'} = $filter if $filter;
			my $json = JSON->new;
			my $pretty = $json->pretty->encode(\%downloads);
			print $pretty;			
		} else {
			print start_html("Zemanta Plugin Downloads");
			print h1("your downloads");
	# previous month
			$sth = $dbh->prepare("SELECT Name, Date, Downloads FROM Downloads WHERE Date LIKE '$lastyear-$lastmonth-%'");
			$sth->execute();
		
			my %lastdownloads;
			while (my ($name, $date, $dlls) = $sth->fetchrow()) {
				#print "$name, $date, $dlls\n";
				$lastdownloads{$name} += $dlls;
				$lastdownloads{'total'} += $dlls;
			}		
			print "<table border='1'><tr>
					<th>plugin</th>
					<th>previous month</th>
					<th>month to date</th>
					<th>EOM estimate</th>
				</tr>";
			foreach my $plugin(sort(keys(%downloads))){
				my $eta = int($downloads{$plugin} * 30 / $day);
				my $test = $lastdownloads{$plugin} || 1;
				print "<tr>
						<td>$plugin</td>
						<td>".$lastdownloads{$plugin}."</td>
						<td>".$downloads{$plugin}."</td>
						<td>$eta (".int(($eta / $test) * 100)."%)</td>
					</tr>";
			}
			print "</table>";	
			$sth->finish();
		    print end_html;
		}
	}
}

$dbh->disconnect();

