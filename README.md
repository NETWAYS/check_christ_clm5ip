check_christ_clm5ip
===================

This plugin queries Christ power panels CLM5-IP on port 10001


### Usage

    check_christ_clm5ip.pl -H <hostname> -m <module> -w <outlet>:<lo>:<hi> -c <outlet>:<lo>:<hi>


Options:

    -H  Hostname

    -m|--module
        Module name, has to be one of: power, temperature, analogIn,digitalIn

         -m power

    -c|--critical
        Critical thresholds, one or more of them. If you want to check multiple sensors at once please separate them by comma (,) - spaces are not allowed:

         --critical out1:1.1:10
         -c out1:0:10,out2::

    -w|--warning
        Warning thresholds, one or more of them. If you want to check multiple sensors at once please separate them by comma (,) - spaces are not allowed:

         --warning out1:2:5
         -w out1:2:5,out2:2.5:4.1

    -h|--help
        Show help

    -V|--version
        Show plugin name and version

