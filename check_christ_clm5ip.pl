#!/usr/bin/perl -w
# $Id$

=pod

=head1 COPYRIGHT

This software is Copyright (c) 2011 NETWAYS GmbH, Thomas Gelf
                               <support@netways.de>

(Except where explicitly superseded by other copyright notices)

=head1 LICENSE

This work is made available to you under the terms of Version 2 of
the GNU General Public License. A copy of that license should have
been provided with this software, but in any event can be snarfed
from http://www.fsf.org.

This work is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 or visit their web page on the internet at
http://www.fsf.org.


CONTRIBUTION SUBMISSION POLICY:

(The following paragraph is not intended to limit the rights granted
to you to modify and distribute this software under the terms of
the GNU General Public License and is only of importance to you if
you choose to contribute your changes and enhancements to the
community by submitting them to NETWAYS GmbH.)

By intentionally submitting any modifications, corrections or
derivatives to this work, or any other work intended for use with
this Software, to NETWAYS GmbH, you confirm that
you are the copyright holder for those contributions and you grant
NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
royalty-free, perpetual, license to use, copy, create derivative
works based on those contributions, and sublicense and distribute
those contributions and any derivatives thereof.

Nagios and the Nagios logo are registered trademarks of Ethan Galstad.

=head1 NAME

check_christ_clm5ip

=head1 SYNOPSIS

check_christ_clm5ip.pl -H <hostname> -m <module> -w <outlet>:<lo>:<hi> \
-c <outlet>:<lo>:<hi>

=head1 OPTIONS

=over

=item   B<-H>

Hostname

=item   B<-m|--module>

Module name, has to be one of: power, temperature, analogIn, digitalIn

 -m power

=item   B<-c|--critical>

Critical thresholds, one or more of them. If you want to check multiple sensors
at once please separate them by comma (,) - spaces are not allowed:

 --critical out1:1.1:10
 -c out1:0:10,out2::

=item   B<-w|--warning>

Warning thresholds, one or more of them. If you want to check multiple sensors
at once please separate them by comma (,) - spaces are not allowed:

 --warning out1:2:5
 -w out1:2:5,out2:2.5:4.1

=item   B<-h|--help>

Show help

=item   B<-V|--version>

Show plugin name and version

=back

=head1 DESCRIPTION

This plugin queries Christ power panels CLM5-IP on port 10001

=cut

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use IO::Socket;
use Data::Dumper;
use strict;

# predeclared subs
use subs qw/help fail fetchPowerInfo fetchTemperature fetchAnalogInputs 
fetchDigitalInputs fetchDigitalOutputs/;

# predeclared vars
use vars qw (
  $PROGNAME
  $VERSION

  %states
  %state_names
  %performance

  @info
  @perflist

  $opt_host
  $opt_module
  $opt_warn
  $opt_crit
  $opt_help
  $opt_version
);

# Main values
$PROGNAME = basename($0);
$VERSION  = '1.0';

# Nagios exit states
%states = (
	'OK'       => 0,
	'WARNING'  => 1,
	'CRITICAL' => 2,
	'UNKNOWN'  => 3
);

# Nagios state names
%state_names = (
	0 => 'OK',
	1 => 'WARNING',
	2 => 'CRITICAL',
	3 => 'UNKNOWN'
);

my $global_state = 'OK';

# Retrieve commandline options
Getopt::Long::Configure('bundling');
GetOptions(
	'h|help'       => \$opt_help,
	'H=s'          => \$opt_host,
	'V|version'    => \$opt_version,
    'm|module=s'   => \$opt_module,
    'w|warning=s'  => \$opt_warn,
    'c|critical=s' => \$opt_crit

) || help( 1, 'ERROR: Please check your options!' );

# Any help needed?
help(99) if $opt_help;
help(-1) if $opt_version;
help(1, 'ERROR: Host is required') unless ($opt_host);
help(1, 'ERROR: Please specify warning threshold') unless ($opt_warn);
help(1, 'ERROR: Please specify critical threshold') unless ($opt_crit);
help(1, 'ERROR: No module has been defined') unless ($opt_module);

my %sensors = ();
my %single_results = (
    'WARNING' => [],
    'CRITICAL' => [],
);

# Check whether given thresholds are OK
parseThresholds('warn', $opt_warn);
parseThresholds('crit', $opt_crit);
checkThresholds();

my $clm_type;
my $clm_model;
my $clm_hwrevision;
my $clm_swrevision;

my $panel = IO::Socket::INET->new(
    Proto     => "tcp",
    PeerAddr  => $opt_host,
    Timeout   => 5,
    PeerPort  => "10001",
);

unless ($panel) {
    fail('CRITICAL', "Cannot connect to Christ panel on $opt_host");
}
$panel->autoflush(1);
getInfo();

if ($clm_type ne 'CLM5IP') {
    fail('CRITICAL', "This plugin does currently not support any panel but" .
         " CLM5IP, $opt_host identifies itself as $clm_type");
}

my $clm_panel_name = getName('clm5ip');
my @data = getData();
my $cnt_out         = 5;
my $cnt_temp        = 2;
my $cnt_in_analog   = 2;
my $cnt_in_digital  = 4;
# my $cnt_out_digital = 1;

# Order is important!
my %power_info = fetchPowerInfo('VA');
my %temp_info = fetchTemperature();
my %analogIn_info = fetchAnalogInputs();
my %digitalIn_info = fetchDigitalInputs();
my %digitalOut_info = fetchDigitalOutputs();

my %result;
my $unit;
if ($opt_module eq 'power') {
    %result = %power_info;
    $unit = 'VA';
} elsif ($opt_module eq 'temperature') {
    %result = %temp_info;
    $unit = 'C';
} elsif ($opt_module eq 'analogIn') {
    %result = %analogIn_info;
} elsif ($opt_module eq 'digitalIn') {
    %result = %digitalIn_info;
} else {
    fail 'CRITICAL', "Got unknown module name";
}

foreach my $sensor (keys %sensors) {
    if (! defined $result{$sensor}) {
        fail 'CRITICAL', "Sensor $sensor (type $opt_module) is not available";
    }
    if ($result{$sensor} eq '---') {
        fail 'CRITICAL', "Sensor $sensor (type $opt_module) doesn't seem to be connected";
    }
    my $res = checkIfValueIsInRange($sensor, $result{$sensor}, \%{$sensors{$sensor}}, $unit);
    raiseGlobalState($res->[0]);
    push @info, sprintf("%s[%s]: %s", $sensor, $res->[0], $res->[1]);
}

my $global_info;
if ($global_state eq 'OK') {
    $global_info = 'All sensors values are fine';
} elsif ($global_state eq 'WARNING') {
    $global_info = join ', ', @{$single_results{$global_state}};
} elsif ($global_state eq 'CRITICAL' && scalar @{$single_results{'WARNING'}} > 0) {
    $global_info .= ' WARNING: ' . join ', ', @{$single_results{'WARNING'}};
}
$global_info .= sprintf " (%s[%s]: HW%s/SW%s)", $clm_type, $clm_model, $clm_hwrevision, $clm_swrevision;

unshift @info, $global_info;

close $panel;

foreach (keys %performance) {
	push @perflist, $_ . '=' . $performance{$_};
}
my $info_delim = ', ';
$info_delim = "\n";
printf('%s %s|%s', $global_state, join($info_delim, @info), join(' ', sort @perflist));
exit $states{$global_state};


sub getNumber
{
    $_ = shift;
    if ($_ eq 'inf') {
        return $_;
    }
    s/^\s+//;
    s/\s+$//;
    return 0 if $_ eq '';
    return ($_ + 0) if /^-?\d+(?:\.\d*)?$/;
    fail 'CRITICAL', "'$_' is not a valid number";
}

sub parseThresholds
{
    my $type = shift;
    my $param = shift;
    my @parts = split /,/, $param;
    foreach my $part (@parts) {
        my @tmp = split /:/, $part;
        if (scalar @tmp < 2) {
            $tmp[1] = 0;
            $tmp[2] = 'inf'; #   = 9**9**9
        }
        if (scalar @tmp < 3) {
            if ($part =~ m/:$/) {
                $tmp[2] = 'inf';
            } else {
                $tmp[2] = $tmp[1];
                $tmp[1] = 0;
            }
        }
        $tmp[1] = getNumber($tmp[1]);
        $tmp[2] = getNumber($tmp[2]);
        $sensors{$tmp[0]}{$type}{'lo'} = $tmp[1];
        $sensors{$tmp[0]}{$type}{'hi'} = $tmp[2];
    }
}

sub checkThresholds
{
    foreach my $key (keys %sensors) {
        if (! $sensors{$key}{'warn'}) {
            fail('CRITICAL', "No WARNING threshold has been provided for $key");
        }
        if (! $sensors{$key}{'crit'}) {
            fail('CRITICAL', "No CRITICAL threshold has been provided for $key");
        }
        if ($sensors{$key}{'warn'}{'lo'} > $sensors{$key}{'warn'}{'lo'})
        {
            fail('CRITICAL', "Low WARNING threshold is lower than CRITICAL for $key");
        }
        if ($sensors{$key}{'warn'}{'hi'} > $sensors{$key}{'crit'}{'hi'})
        {
            fail('CRITICAL', "Upper WARNING threshold is higher than CRITICAL for $key");
        }
    }
}

sub getName {
    my $mod = shift;
    my @res = split(/;/, runCmd('gn ' . $mod));
    if (@res < 2) {
        fail('CRITICAL', "Unable to retrieve name for '$mod' from '$opt_host'"); 
    }
    pop @res;
    chomp $res[0];
    return $res[0];
}

sub fetchPowerInfo()
{
    my %res;
    my $key;
    $key = $_[0] if defined $_[0];
    for (my $i = 1; $i <= $cnt_out; $i++) {
        my %info = (
            W      => shift @data, # Wirkleistung
            VA     => shift @data, # Scheinleistung
            var    => shift @data, # Blindleistung
            V      => shift @data, # Spannung
            A      => shift @data, # Strom
            status => shift @data  # Status
        );
        foreach my $k (keys %info) {
            $info{$k} =~ s/,/./;
        }
        if ($key) {
            $res{ getName('o' . $i) } = $info{$key};
        } else {
            $res{ getName('o' . $i) } = \%info;
        }
    }
    return %res;
}

sub fetchTemperature()
{
    my %res;
    for (my $i = 1; $i <= $cnt_temp; $i++) {
        my $name = getName('t' . $i);
        $res{$name} = shift @data;
        $res{$name} =~ s/,/./;
    }
    return %res;
}

sub fetchAnalogInputs()
{
    my %res;
    for (my $i = 1; $i <= $cnt_in_analog; $i++) {
        my $name = getName('ain' . $i);
        $res{$name} = shift @data;
        $res{$name} =~ s/,/./;
    }
    return %res;
}

sub fetchDigitalInputs()
{
    my %res;
    for (my $i = 1; $i <= $cnt_in_digital; $i++) {
        my $name = getName('din' . $i);
        $res{$name} = shift @data;
        $res{$name} =~ s/,/./;
    }
    return %res;
}

# Currently not in use
sub fetchDigitalOutputs()
{
    my %res;
    my $name = getName('dout');
    $res{$name} = shift @data;
    $res{$name} =~ s/,/./;
    return %res;
}

# Lot of redundant code for userfriendly info texts
sub checkIfValueIsInRange
{
    my $name = $_[0];
    my $val = $_[1];
    my %sensor = %{ $_[2] };
    my $unit = '';
    $unit = $_[3] if defined $_[3];

    $performance{sprintf('%s_%s', $opt_module, $name)} = sprintf(
	    "%.2f%s;%.1f:%.1f;%.1f:%.1f",
        $val,
        $unit, # really?
        $sensor{'warn'}{'lo'},
        $sensor{'warn'}{'hi'},
        $sensor{'crit'}{'lo'},
        $sensor{'crit'}{'hi'}
    );

    if ($val < $sensor{'crit'}{'lo'}) {
        push @{$single_results{'CRITICAL'}}, $name;
        return ['CRITICAL', sprintf(
            "Measured value (%.1f%s) is lower than the critical threshold %s%s",
            $val,
            $unit,
            $sensor{'crit'}{'lo'},
            $unit
        )];
    }
    if ($val > $sensor{'crit'}{'hi'}) {
        push @{$single_results{'CRITICAL'}}, $name;
        return ['CRITICAL', sprintf(
            "Measured value (%.1f%s) is higher than the critical threshold %.1f%s",
            $val,
            $unit,
            $sensor{'crit'}{'hi'},
            $unit
        )];
    }
    if ($val < $sensor{'warn'}{'lo'}) {
        push @{$single_results{'WARNING'}}, $name;
        return ['WARNING', sprintf(
            "Measured value (%.1f%s) is lower than the warning threshold %.1f%s",
            $val,
            $unit,
            $sensor{'warn'}{'lo'},
            $unit
        )];
    }
    if ($val > $sensor{'warn'}{'hi'}) {
        push @{$single_results{'WARNING'}}, $name;
        return ['WARNING', sprintf(
            "Measured value (%.1f%s) is higher than the warning threshold %.1f%s",
            $val,
            $unit,
            $sensor{'warn'}{'hi'},
            $unit
        )];
    }
    return ['OK', sprintf(
        "Measured value (%.1f%s) is within the configured thresholds (w%.1f:%.1f/c%.1f:%.1f)",
            $val,
            $unit,
            $sensor{'warn'}{'lo'},
            $sensor{'warn'}{'hi'},
            $sensor{'crit'}{'lo'},
            $sensor{'crit'}{'hi'}
    )];
}

sub getInfo {
    my @res = split(/;/, runCmd('i'));
    pop @res;
    if (@res < 4) {
        fail('CRITICAL', "Unable to retrieve system information for $opt_host");
    }
    $clm_type = $res[0];
    $clm_model = $res[1];
    $clm_hwrevision = $res[2];
    $clm_swrevision = $res[3];
    $clm_model =~ s/\s+//g;
    $clm_hwrevision =~ s/\s+//g;
    $clm_swrevision =~ s/\s+//g;
    chomp($clm_type);
    chomp($clm_model);
    chomp($clm_hwrevision);
    chomp($clm_swrevision);
}

sub getData {
    my $data = runCmd('get data');
    my @res = split(/;/, $data);
    if (@res != 40) {
        my $cnt = scalar @res;
        fail('CRITICAL', "Unable to retrieve performance data for $opt_host (got $cnt values instead of 40)");
    }
    return @res;
}

sub runCmd {
    my $ret;
    my $cmd = shift;
    print $panel "$cmd\r\n";
    $ret = <$panel>;
    if ($ret eq "" || $ret =~ /unknown/) {
        fail('CRITICAL', "Running '$cmd' on $opt_host failed");
    }
    return $ret;
}

# Raise global state if given one is higher than the current state
sub raiseGlobalState {
	my @states = @_;
	foreach my $state (@states) {
		# Pay attention: UNKNOWN > CRITICAL
		if ($states{$state} > $states{$global_state}) {
			$global_state = $state;
		}
	}
}

# Print error message and terminate program with given status code
sub fail {
	my ($state, $msg) = @_;
	print $state_names{ $states{$state} } . ": $msg\n";
	exit $states{$state};
}

# help($level, $msg);
# prints some message and the POD DOC
sub help {
	my ($level, $msg) = @_;
	$level = 0 unless ($level);
	if ($level == -1) {
		print "$PROGNAME - Version: $VERSION\n";
		exit $states{UNKNOWN};
	}
	pod2usage({
		-message => $msg,
		-verbose => $level
	});
	exit $states{'UNKNOWN'};
}

1;

