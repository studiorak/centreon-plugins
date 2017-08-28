#
# Copyright 2017 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package network::alcatel::isam::snmp::mode::hubsapusage;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use centreon::plugins::statefile;

my $instance_mode;

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'sap', type => 1, cb_prefix_output => 'prefix_sap_output', message_multiple => 'All SAP are ok', skipped_code => { -10 => 1 } },
    ];
    
    $self->{maps_counters}->{sap} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'status' }, { name => 'admin' }, { name => 'display' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
        { label => 'in-traffic', set => {
                key_values => [ { name => 'in', diff => 1 }, { name => 'display' } ],
                per_second => 1,
                closure_custom_calc => $self->can('custom_sap_calc'), closure_custom_calc_extra_options => { label_ref => 'in' },
                closure_custom_output => $self->can('custom_sap_output'),
                closure_custom_perfdata => $self->can('custom_sap_perfdata'),
                closure_custom_threshold_check => $self->can('custom_qsap_threshold'),
            }
        },
        { label => 'out-traffic', set => {
                key_values => [ { name => 'out', diff => 1 }, { name => 'display' } ],
                per_second => 1,
                closure_custom_calc => $self->can('custom_sap_calc'), closure_custom_calc_extra_options => { label_ref => 'out' },
                closure_custom_output => $self->can('custom_sap_output'),
                closure_custom_perfdata => $self->can('custom_sap_perfdata'),
                closure_custom_threshold_check => $self->can('custom_sap_threshold'),
            }
        },
    ];
}

sub custom_status_threshold {
    my ($self, %options) = @_;
    my $status = 'ok';
    my $message;

    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };

        my $label = $self->{label};
        $label =~ s/-/_/g;
        if (defined($instance_mode->{option_results}->{'critical_' . $label}) && $instance_mode->{option_results}->{'critical_' . $label} ne '' &&
            eval "$instance_mode->{option_results}->{'critical_' . $label}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{'warning_' . $label}) && $instance_mode->{option_results}->{'warning_' . $label} ne '' &&
                 eval "$instance_mode->{option_results}->{'warning_' . $label}") {
            $status = 'warning';
        }

        $instance_mode->{last_status} = 0;
        if ($self->{result_values}->{admin} eq 'up') {
            $instance_mode->{last_status} = 1;
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_status_output {
    my ($self, %options) = @_;
    my $msg = 'Status : ' . $self->{result_values}->{status} . ' (admin: ' . $self->{result_values}->{admin} . ')';

    return $msg;
}

sub custom_status_calc {
    my ($self, %options) = @_;

    $self->{result_values}->{admin} = $options{new_datas}->{$self->{instance} . '_admin'};
    $self->{result_values}->{status} = $options{new_datas}->{$self->{instance} . '_status'};
    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    return 0;
}

sub custom_sap_perfdata {
    my ($self, %options) = @_;
    
    my $extra_label = '';
    if (!defined($options{extra_instance}) || $options{extra_instance} != 0) {
        $extra_label .= '_' . $self->{result_values}->{display};
    }
    
    my ($warning, $critical);
    if ($instance_mode->{option_results}->{units_traffic} eq '%' && defined($self->{result_values}->{speed})) {
        $warning = $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{label}, total => $self->{result_values}->{speed}, cast_int => 1);
        $critical = $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{label}, total => $self->{result_values}->{speed}, cast_int => 1);
    } elsif ($instance_mode->{option_results}->{units_traffic} eq 'b/s') {
        $warning = $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{label});
        $critical = $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{label});
    }
    
    $self->{output}->perfdata_add(label => 'traffic_' . $self->{result_values}->{label} . $extra_label, unit => 'b/s',
                                  value => sprintf("%.2f", $self->{result_values}->{traffic}),
                                  warning => $warning,
                                  critical => $critical,
                                  min => 0, max => $self->{result_values}->{speed});
}

sub custom_sap_threshold {
    my ($self, %options) = @_;
    
    my $exit = 'ok';
    if ($instance_mode->{option_results}->{units_traffic} eq '%' && defined($self->{result_values}->{speed})) {
        $exit = $self->{perfdata}->threshold_check(value => $self->{result_values}->{traffic_prct}, threshold => [ { label => 'critical-' . $self->{label}, exit_litteral => 'critical' }, { label => 'warning-' . $self->{label}, exit_litteral => 'warning' } ]);
    } elsif ($instance_mode->{option_results}->{units_traffic} eq 'b/s') {
        $exit = $self->{perfdata}->threshold_check(value => $self->{result_values}->{traffic}, threshold => [ { label => 'critical-' . $self->{label}, exit_litteral => 'critical' }, { label => 'warning-' . $self->{label}, exit_litteral => 'warning' } ]);
    }
    return $exit;
}

sub custom_sap_output {
    my ($self, %options) = @_;
    
    my ($traffic_value, $traffic_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{traffic}, network => 1);
    my ($total_value, $total_unit);
    if (defined($self->{result_values}->{speed}) && $self->{result_values}->{speed} =~ /[0-9]/) {
        ($total_value, $total_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{speed}, network => 1);
    }
   
    my $msg = sprintf("Traffic %s : %s/s (%s on %s)",
                      ucfirst($self->{result_values}->{label}), $traffic_value . $traffic_unit,
                      defined($self->{result_values}->{traffic_prct}) ? sprintf("%.2f%%", $self->{result_values}->{traffic_prct}) : '-',
                      defined($total_value) ? $total_value . $total_unit : '-');
    return $msg;
}

sub custom_sap_calc {
    my ($self, %options) = @_;
    
    return -10 if (defined($instance_mode->{last_status}) && $instance_mode->{last_status} == 0);
    $self->{result_values}->{label} = $options{extra_options}->{label_ref};
    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    $self->{result_values}->{traffic} = ($options{new_datas}->{$self->{instance} . '_' . $self->{result_values}->{label}} - $options{old_datas}->{$self->{instance} . '_' . $self->{result_values}->{label}}) / $options{delta_time};
    if (defined($instance_mode->{option_results}->{'speed_' . $self->{result_values}->{label}}) && $instance_mode->{option_results}->{'speed_' . $self->{result_values}->{label}} =~ /[0-9]/) {
        $self->{result_values}->{traffic_prct} = $self->{result_values}->{traffic} * 100 / ($instance_mode->{option_results}->{'speed_' . $self->{result_values}->{label}} * 1000 * 1000);
        $self->{result_values}->{speed} = $instance_mode->{option_results}->{'speed_' . $self->{result_values}->{label}} * 1000 * 1000;
    }
    return 0;
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, statefile => 1);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "reload-cache-time:s" => { name => 'reload_cache_time', default => 300 },
                                  "display-name:s"      => { name => 'display_name', default => '%{SvcName}.%{IfName}.%{SapEncapName}' },
                                  "filter-name:s"       => { name => 'filter_name' },
                                  "speed-in:s"          => { name => 'speed_in' },
                                  "speed-out:s"         => { name => 'speed_out' },
                                  "units-traffic:s"     => { name => 'units_traffic', default => '%' },
                                  "warning-status:s"    => { name => 'warning_status', default => '' },
                                  "critical-status:s"   => { name => 'critical_status', default => '%{admin} =~ /up/i and %{status} !~ /up/i' },
                                });
    
    $self->{statefile_cache} = centreon::plugins::statefile->new(%options);
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);
    
    $instance_mode = $self;
    $self->change_macros();
    $self->{statefile_cache}->check_options(%options);
}

sub change_macros {
    my ($self, %options) = @_;
    
    foreach (('warning_status', 'critical_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

sub prefix_sap_output {
    my ($self, %options) = @_;
    
    return "SAP '" . $options{instance_value}->{display} . "' ";
}

sub get_display_name {
    my ($self, %options) = @_;
    
    my $display_name = $self->{option_results}->{display_name};
    $display_name =~ s/%\{(.*?)\}/$options{$1}/ge;
    return $display_name;
}

my %map_admin = (1 => 'up', 2 => 'down');
my %map_oper = (1 => 'up', 2 => 'down', 3 => 'ingressQosMismatch',
    4 => 'egressQosMismatch', 5 => 'portMtuTooSmall', 6 => 'svcAdminDown',
    7 => 'iesIfAdminDown'
);

my $mapping = {
    sapAdminStatus              => { oid => '.1.3.6.1.4.1.6527.3.1.2.4.3.2.1.6', map => \%map_admin },
    sapOperStatus               => { oid => '.1.3.6.1.4.1.6527.3.1.2.4.3.2.1.7', map => \%map_oper },
    fadSapStatsIngressOctets    => { oid => '.1.3.6.1.4.1.637.61.1.85.17.2.2.1.2' },
    fadSapStatsEgressOctets     => { oid => '.1.3.6.1.4.1.637.61.1.85.17.2.2.1.4' },
};

my $oid_sapDescription = '.1.3.6.1.4.1.6527.3.1.2.4.3.2.1.5';
my $oid_svcName = '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.29';
my $oid_ifName  = '.1.3.6.1.2.1.31.1.1.1.2';

sub reload_cache {
    my ($self, %options) = @_;
    
    my $snmp_result = $options{snmp}->get_multiple_table(oids => [ 
            { oid => $oid_sapDescription }, 
            { oid => $oid_svcName },
            { oid => $oid_ifName },
        ],
        nothing_quit => 1);
    $datas->{last_timestamp} = time();
    $datas->{snmp_result} = $snmp_result;
   
    if (scalar(keys %{$datas->{snmp_result}->{$oid_sapDescription}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "Can't construct cache...");
        $self->{output}->option_exit();
    }

    $self->{statefile_cache}->write(data => $datas);
}

sub manage_selection {
    my ($self, %options) = @_;
    
    if ($options{snmp}->is_snmpv1()) {
        $self->{output}->add_option_msg(short_msg => "Need to use SNMP v2c or v3.");
        $self->{output}->option_exit();
    }
    
    my $has_cache_file = $self->{statefile_cache}->read(statefile => 'cache_alcatel_isam_' . $options{snmp}->get_hostname()  . '_' . $options{snmp}->get_port() . '_' . $self->{mode});
    my $timestamp_cache = $self->{statefile_cache}->get(name => 'last_timestamp');
    if ($has_cache_file == 0 || !defined($timestamp_cache) ||
        ((time() - $timestamp_cache) > (($self->{option_results}->{reload_cache_time}) * 60))) {
        $self->reload_cache();
        $self->{statefile_cache}->read();
    }

    my $snmp_result = $self->{statefile_cache}->get(name => 'snmp_result');

    $self->{sap} = {};
    foreach my $oid (keys %{$snmp_result->{$oid_sapDescription}}) {
        next if ($oid !~ /^$oid_sapDescription\.(.*?)\.(.*?)\.(.*?)$/);
        # $SvcId and $SapEncapValue is the same. We use service table
        my ($SvcId, $SapPortId, $SapEncapValue) = ($1, $2, $3);
        my $instance = $SvcId . '.' . $SapPortId . '.' . $SapEncapValue;
        
        my $SapDescription = $snmp_result->{$oid_sapDescription}->{$oid} ne '' ?
            $snmp_result->{$oid_sapDescription}->{$oid} : 'unknown';
        my $SvcName = defined($snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SvcId}) && $snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SvcId} ne '' ?
           $snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SvcId} : $SvcId;
        my $IfName = defined($snmp_result->{$oid_ifName}->{$oid_ifName . '.' . $SapPortId}) && $snmp_result->{$oid_ifName}->{$oid_ifName . '.' . $SapPortId} ne '' ?
           $snmp_result->{$oid_ifName}->{$oid_ifName . '.' . $SapPortId} :  $SapPortId;
        my $SapEncapName = defined($snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SapEncapValue}) && $snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SapEncapValue} ne '' ?
           $snmp_result->{$oid_svcName}->{$oid_svcName . '.' . $SapEncapValue} : $SapEncapValue;
        
        my $name = $self->get_display_name(
            SapDescription => $SapDescription, 
            SvcName => $SvcName,
            SapEncapName => $SapEncapName, 
            IfName => $IfName,
            SvcId => $SvcId, 
            SapPortId => $SapPortId, 
            SapEncapValue => $SapEncapValue);
        if (defined($self->{option_results}->{filter_name}) && $self->{option_results}->{filter_name} ne '' &&
            $name !~ /$self->{option_results}->{filter_name}/) {
            $self->{output}->output_add(long_msg => "skipping  '" . $name . "': no matching filter.", debug => 1);
            next;
        }
        
        $self->{sap}->{$instance} = { display => $name };
    }
    
    $options{snmp}->load(oids => [$mapping->{fadSapStatsIngressOctets}->{oid}, 
        $mapping->{fadSapStatsEgressOctets}->{oid},
        $mapping->{sapAdminStatus}->{oid}, $mapping->{sapOperStatus}->{oid}], 
        instances => [keys %{$self->{sap}}], instance_regexp => '(\d+\.\d+\.\d+)$');
    $snmp_result = $options{snmp}->get_leef(nothing_quit => 1);
    foreach (keys %{$self->{sap}}) {
        my $result = $options{snmp}->map_instance(mapping => $mapping, results => $snmp_result, instance => $_);        
        $self->{sap}->{$_}->{in} = $result->{fadSapStatsIngressOctets} * 8;
        $self->{sap}->{$_}->{out} = $result->{fadSapStatsEgressOctets} * 8;
        $self->{sap}->{$_}->{status} = $result->{sapOperStatus};
        $self->{sap}->{$_}->{admin} = $result->{sapAdminStatus};
    }

    if (scalar(keys %{$self->{sap}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No SAP found.");
        $self->{output}->option_exit();
    }
    
    $self->{cache_name} = "alcatel_isam_" . $self->{mode} . '_' . $options{snmp}->get_hostname()  . '_' . $options{snmp}->get_port() . '_' .
        (defined($self->{option_results}->{filter_counters}) ? md5_hex($self->{option_results}->{filter_counters}) : md5_hex('all')) . '_' .
        (defined($self->{option_results}->{filter_name}) ? md5_hex($self->{option_results}->{filter_name}) : md5_hex('all'));
}

1;

__END__

=head1 MODE

Check SAP QoS usage.

=over 8

=item B<--display-name>

Display name (Default: '%{SvcName}.%{IfName}.%{SapEncapName}').
Can also be: %{SapDescription}, %{SapPortId}

=item B<--filter-name>

Filter by SAP name (can be a regexp).

=item B<--speed-in>

Set interface speed for incoming traffic (in Mb).

=item B<--speed-out>

Set interface speed for outgoing traffic (in Mb).

=item B<--units-traffic>

Units of thresholds for the traffic (Default: '%') ('%', 'b/s').

=item B<--warning-status>

Set warning threshold for ib status.
Can used special variables like: %{admin}, %{status}, %{display}

=item B<--critical-status>

Set critical threshold for ib status (Default: '%{admin} =~ /up/i and %{status} !~ /up/i').
Can used special variables like: %{admin}, %{status}, %{display}

=item B<--warning-*>

Threshold warning.
Can be: 'in-traffic', 'out-traffic'.

=item B<--critical-*>

Threshold critical.
Can be: 'in-traffic', 'out-traffic'.

=item B<--reload-cache-time>

Time in seconds before reloading cache file (default: 300).

=back

=cut