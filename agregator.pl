#!/usr/bin/perl -w 

# todo:
# 	+ read plugins list from file
#	+ read secrets from file
#	+ upload to git / write readme file
#	+ export html report for dashboard
#	+ get historic data
#	+ incremental saving only
#	- export prettier report for dashboard
#	- export API - days and months by plugin or all
#	- reconicile plugin names with panco
#	- rewrite in python :)

use strict;

my $verbose = 0;	# will tell what it's doing
my $debug = 0;		# will only print, not save to database
my $history = 0;	# try fetching history from all sources
my $dontoverwrite = 1; 	# wont store data if exists by default

use JSON;
use utf8;
use IO::Socket::SSL;
use WWW::Mechanize;
use DBI;
use POSIX;
use File::Basename;

my $curr_path = dirname(__FILE__);

print "DEBUG MODE, NOTHING WILL BE SAVED!" if $debug;
my $dbh = DBI->connect(          
	    "dbi:SQLite:dbname=" . $curr_path . "/data.db", 
	    "",                          
	    "",                          
	    { RaiseError => 1 },         
	) or die $DBI::errstr;

#$dbh->do("DROP TABLE IF EXISTS Downloads");
$dbh->do("CREATE TABLE IF NOT EXISTS Downloads(Id INT PRIMARY KEY,
 Name TEXT,
 Date TEXT,
 Downloads INT,
 CONSTRAINT unq UNIQUE (Name,
 Date,
 Downloads))");

my %plugins;
&read_plugins_settings;

my %secrets;
&read_secrets;

my $json = JSON->new->allow_nonref;

foreach my $plugin (keys(%plugins)) {
	warn $plugin if $verbose; 
	my $url = $plugins{$plugin};
	warn "\t$url" if $debug;
	my $parser = 0;
# guess parser
	if ($url =~ /wordpress\.org\/plugins\/(.*)\//) {
		my $slug = $1;
		$parser = 1;
		warn "\t".$parser if $debug;
		my $json = &get_wordpress($url, $slug);
		&store_wordpress($plugin, $url, $json);
	} elsif ($url =~ /mozilla\.org\/en-US\/firefox\/addon\/(.*)\//) {
		my $slug = $1;
		$parser = 2;
		warn "\t".$parser if $debug;
		my $json = &get_mozilla($url, $slug);
		&store_mozilla($plugin, $url, $json);
	} elsif ($url =~ /google\.com\/webstore\/detail\/(.*?)\/(.*)/) {
		my $slug = $1;
		my $token = $2;
		$parser = 3;
		warn "\t".$parser if $debug;
		my $json = &get_chrome($url, $token);
		&store_chrome($plugin, $url, $json);
	} elsif ($url =~ /\/\/(.*?)\/(.*)/) {	# fallback to bitly
		my $customurl = $1;
		my $slug = $2;
		$parser = 4;
		warn "\t".$parser if $debug;
		my $json = &get_bitly($url, $slug);
		&store_bitly($plugin, $url, $json);
	}
	warn "\tdone " if $debug;
}

$dbh->disconnect();

print "DEBUG MODE, NOTHING WILL WAS SAVED!" if $debug;

# --- scrapers ---

# official undocumented api:
#	http://api.wordpress.org/stats/plugin/1.0/downloads.php?limit=730&slug=zemanta
sub get_wordpress {
	my ($url, $slug) = @_;
	my $mech = WWW::Mechanize->new();
	my $limit = 5;
		$limit = 730 if $history;
	$mech->get("http://api.wordpress.org/stats/plugin/1.0/downloads.php?limit=$limit&slug=$slug");
	#my $response = decode_json($mech->text());
	my $response = JSON->new->utf8->decode($mech->text());
	return $response;
}

# scraping mozilla directory for 100 days at a time
# https://addons.mozilla.org/en-US/firefox/users/login?to=%2Fen-US%2Ffirefox%2Faddon%2Fzemanta%2Fstatistics%2Fdownloads%2Fsources%2F%3Flast%3D90
# https://addons.mozilla.org/en-US/firefox/addon/zemanta/statistics/sources-day-20131116-20140214.json
sub get_mozilla {
	my ($url, $slug) = @_;
	my $mech = WWW::Mechanize->new(ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
		verify_hostname => 0, # this key is likely going to be removed in future LWP >6.04
	});

	my $todate = strftime '%Y%m%d', localtime;
	my $fromtime = time() - 100 * 24 * 60 * 60;	# last 100 days to avoid timeouts
	my $fromdate = strftime '%Y%m%d', localtime $fromtime;

	$mech->get("https://addons.mozilla.org/en-US/firefox/users/login");
	$mech->form_number(2);
	$mech->field("username", $secrets{'mozilla'}{'username'});
	$mech->field("password", $secrets{'mozilla'}{'password'});	
	$mech->submit();

	my $request = "https://addons.mozilla.org/en-US/firefox/addon/".$slug."/statistics/sources-day-".$fromdate."-".$todate.".json";
	$mech->get("https://addons.mozilla.org/en-US/firefox/addon/$slug/statistics/sources-day-$fromdate-$todate.json");
	my $response = decode_json($mech->text());

	if ($history) {
		my $addedtime = mktime(0,0,0,1,1,108);	# todo - make into variable
		warn "\tadded: $addedtime" if $verbose;

		# circle trough history until first date
		do {
			$todate = $fromdate;
			$fromtime -= 100 * 24 * 60 * 60;
			$fromdate = strftime '%Y%m%d', localtime $fromtime;

			warn "\t$fromdate" if $verbose;

			my $request = "https://addons.mozilla.org/en-US/firefox/addon/".$slug."/statistics/sources-day-".$fromdate."-".$todate.".json";
			$mech->get("https://addons.mozilla.org/en-US/firefox/addon/$slug/statistics/sources-day-$fromdate-$todate.json");

			my $historyresponse = decode_json($mech->text());
			push(@{$response}, @{$historyresponse});
			
		} while ($fromtime > $addedtime);	# ? this works because it will run last time when $fromtime is already under
		# stuff stats into response json

	}

	return $response;
}

# scrape chrome directory with reverse-engineered json call that returs last 3 months.
# https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fchrome.google.com%2Fwebstore%2Fcategory%2Fapps&service=chromewebstore&sarp=1
# https://chrome.google.com/webstore/developer/stats/fejeknoakjeblidffkajbioncodnmhge
# https://accounts.google.com/ServiceLogin?service=chromewebstore&passive=1209600&continue=https://chrome.google.com/webstore/developer/stats/fejeknoakjeblidffkajbioncodnmhge&followup=https://chrome.google.com/webstore/developer/stats/fejeknoakjeblidffkajbioncodnmhge
sub get_chrome {
	my ($url, $slug) = @_;
	my $mech = WWW::Mechanize->new(ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,

		verify_hostname => 0,
 # this key is likely going to be removed in future LWP >6.04
	});
	$mech->get("https://accounts.google.com/ServiceLogin?service=chromewebstore");
	$mech->form_number(1);
	$mech->field("Email", $secrets{'chrome'}{'Email'});
	$mech->field("Passwd", $secrets{'chrome'}{'Passwd'});	
	$mech->submit();
	$mech->get("https://chrome.google.com/webstore/developer/data?tq=base_stats%3A".$slug."&tqx=reqId%3A0");
	my $returned_text = $mech->text() . "";
	$returned_text =~ s/\R//g;
	$returned_text =~ s/,,/,/g;
	my $response = decode_json($returned_text);
	return $response;
}

# bitly api that returns 1000 at a time
# API Address: https://api-ssl.bitly.com
# GET /v3/link/clicks?access_token=ACCESS_TOKEN&link=http%3A%2F%2Fbit.ly%2F1234
sub get_bitly {
	my ($url, $slug) = @_;
	my $mech = WWW::Mechanize->new(ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
		verify_hostname => 0,
 # this key is likely going to be removed in future LWP >6.04
	});
	my $token = $secrets{'bitly'}{'token'};
	my $limit = 5;	# default to updating last 5 days
		$limit = 1000 if $history;
	my $request = "https://api-ssl.bitly.com/v3/link/clicks?access_token=".$token."&rollup=false&limit=".$limit."&link=".$url;
	$mech->get($request);
	my $response = decode_json($mech->text());
	return $response;
}

# --- store data ---

sub store_wordpress {
	my ($name, $url, $json) = @_;
	foreach my $date (keys(%{$json})) {
		my $dlls = $json->{$date};
		&store_row($name, $date, $dlls);
	}
}

sub store_mozilla {
	my ($name, $url, $json) = @_;
	foreach my $day (@{$json}) {
		my $date = $day->{'date'};
		my $dlls = $day->{'count'};
		&store_row($name, $date, $dlls);
	}
}

sub store_chrome {
	my ($name, $url, $json) = @_;
	foreach my $day (@{$json->{'table'}->{'rows'}}) {
		my @day = @{$day->{'c'}};
		my $date = $day[0]->{'v'};
		my $dlls = $day[2]->{'v'};

		if ($date =~ /Date\((\d+),(\d+),(\d+)\)/) {
			my $year = $1;
			my $month = $2 + 1;
				$month = '0'.$month if ($month < 10);
			my $dayy = $3;
				$dayy = '0'.$dayy if ($dayy < 10);

			$date = "$year-$month-$dayy";
			&store_row($name, $date, $dlls);
		}
	}
}

sub store_bitly {
	my ($name, $url, $json) = @_;
	foreach my $day (@{$json->{'data'}->{'link_clicks'}}) {
		my $date = $day->{'dt'};
			$date = strftime '%Y-%m-%d', localtime $date;
		my $dlls = $day->{'clicks'};
		&store_row($name, $date, $dlls);
	}
}

sub store_row {
	my ($name, $date, $dlls) = @_;
	print "$date - $dlls\n" if $debug or $verbose;
	my $sth = $dbh->prepare("SELECT * from Downloads WHERE Name='$name' AND Date='$date';");
		$sth->execute();
	if ($dontoverwrite and !$sth->fetchrow_array) {
		print "\tinserting row\n" if $debug or $verbose;
		$dbh->do("INSERT OR IGNORE INTO Downloads(Name, Date, Downloads) VALUES ('$name', '$date', '$dlls')") if !$debug;
	} else {
		print "\tskipping row, found data\n" if $debug or $verbose;
	}
}

# --- settings files ---

sub read_plugins_settings {
	foreach my $line (readpipe("cat " . $curr_path . "/plugins.txt")) {
		chop $line;
		my @line = split/\t/,$line;
		$plugins{$line[0]} = $line[1];
	}
}

sub read_secrets {
	foreach my $line (readpipe("cat " . $curr_path . "/secrets.txt")) {
		chop $line;
		my @line = split/\t/,$line;
		my $name = shift(@line);
		#$secrets{$name} = @line;

		while ($#line > 0) {
		    my $key = shift @line;
		    $secrets{$name}{$key} = shift @line;
		}	
	}
}
