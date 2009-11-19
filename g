#!/usr/bin/perl -w
use strict;

use sigtrap die => 'normal-signals';

use constant GOROOT => $ENV{GOROOT}  || die "Missing GOROOT\n";
use constant GOARCH => $ENV{GOARCH}  || die "Missing GOARCH\n";
use constant GOOS   => $ENV{GOOS}    || die "Missing GOOS\n";

use constant GO => {
    arm   => 5,
    amd64 => 6,
    386   => 8,
}->{(GOARCH)} ||  die "Unknown GOARCH";

use constant COMPILER => GO . 'g';
use constant LINKER   => GO . 'l';
use constant EXE      => GO. '.out';

use Fatal qw(open close);

if(@ARGV){ # like an interpreter
    my($source) = shift @ARGV;

    go_run($source, @ARGV);
}
else { # like a shell
    my $libdir = sprintf '%s/pkg/%s_%s', GOROOT, GOOS, GOARCH;
    -d $libdir or die "Missing go package directry ($libdir)\n";

    require File::Find;

    my @packages;
    File::Find::find(sub{
        return if !s/\.a \z//xms;

        push @packages, $_;
    }, $libdir);

    my $packages_re = join('|', @packages);

    my $go_file = "$$.go";
    END{ unlink $go_file if defined $go_file }

    $| = 1;
    for(print "\n", "go> "; <STDIN>; print "\n", "go> "){
        my @imports = $_ =~ /($packages_re)\./xmsg;

        open my($out), '>', $go_file;
        print $out go_main($_, @imports);
        close $out;

        go_run($go_file);
    }
    print "\n";
}

sub go_run{
    my($source, @args) = @_;

    # compile
    system(COMPILER, $source) == 0 or return;
    # link
    (my $imd = $source) =~ s/\.go \z/'.' . GO/xmse;
    system(LINKER, $imd) == 0 or return;

    # exec
    system('./' . EXE, @args) == 0 or return;

    return;
}

sub go_main {
    my($source, @imports) = @_;

    my $import_directive = '';
    if(@imports){
        $import_directive = sprintf 'import(%s)', join ';', map{ qq{"$_"} } @imports;
    }
    return sprintf <<'__GO__', $import_directive, $source;
package main
%s
func main() {
    %s;
}
__GO__
}
