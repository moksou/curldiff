#!/usr/bin/perl

use strict;
use Config::Simple;
use WWW::Curl::Easy;
use File::Basename;
use File::Path qw(make_path remove_tree);
use URI::Split qw(uri_split uri_join);
use Text::Diff;

my ($host, $diffpage) = @ARGV;
my ($hscheme, $hauth, $hpath, $hquery) = uri_split($host);
if(!$host || !$hscheme || !$hauth) { print "usage: ./curlGet.pl http(s)://hostname.com/\n"; exit; }
$hpath = "/index.html" unless $hpath;
my ($pscheme, $pauth, $ppath, $pquery);

my $cfg = new Config::Simple('curldiff.cfg');

my $workdir = $cfg->param('Workdir');
my @ext     = $cfg->param('Extensions');
my $mkdiff  = $cfg->param('Mkdiff');

my (@linkstack, @filestack);
push @linkstack, $host;

foreach my $link (@linkstack) {
    ($pscheme, $pauth, $ppath, $pquery) = uri_split($link);
    my $html = curl_get($link);
    my @links = $html =~ m/(?:href=["']?)([^\s\>"']+(?=["'])?)/g;
#     print join("\n", @links); print "\n";
    
    foreach my $link (@links) {
        $link = url_parse($link);
        unless ($link ~~ @linkstack) { push @linkstack, $link if $link; }
    }
    
    my $filename = create_file($link, $html);
}

if ($mkdiff) {
    foreach my $file (@filestack) {
        if (grep { /\Q$diffpage\E$/ } $file) {
            $diffpage = $file;
            last;
        }
    }
    foreach my $file (@filestack) {
        $file .= "index.html" if grep { /\/$/ } $file;
        mkdiff($diffpage, $file, ($file eq $filestack[-1]) ? 1 : 0) if @ext && $file ne $diffpage;
    }
}

sub curl_get
{
    my $page = shift @_;
    my $curl = new WWW::Curl::Easy->new;
    my $output;
    
    $curl->setopt(CURLOPT_URL, $page);
    $curl->setopt(CURLOPT_WRITEDATA, \$output);
    $curl->setopt(CURLOPT_ENCODING, "");
    $curl->setopt(CURLOPT_USERAGENT, "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 1.0.3705; .NET CLR 1.1.4322)");
    $curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
    my $code = $curl->perform;
    if ($code == 0) {
        return $output;
    } else {
        print "curl error: $code\n";
        return 0;
    }
}

sub create_file
{
    my $link = shift @_;
    my $data = shift @_;
    return 0 unless $data;
    
    my ($filename) = grep { s/https?\:\/\/// } $link;
    $filename =  $workdir . $filename;
    if ($filename =~ /[^\!\?]\/$/) {
        make_path($filename);
        $filename .= "index.html";
    }
    unless (-d dirname($filename)) {
        make_path(dirname($filename));
    }
    unless (-e $filename) {
        print $filename; print "\n";
        open  FILE, '>' . $filename;
        print FILE $data;
        close FILE;
        push @filestack, $filename;
    } else {
        print "file $filename exists\n";
    }
    return $filename;
}

sub url_parse
{
    my $url = shift @_;
    my ($scheme, $auth, $path, $query) = uri_split($url);
    if (@ext) {
        my $c;
        foreach my $arg (@ext) {
            $c++ if $path && index($path, $arg) == -1 && $path !~ /\/$/;
        } 
        return 0 if $c == scalar @ext;
    }
#     return 0                 if     $path =~ /index\.\w+/;
    return 0                 if     $scheme && $scheme ne $hscheme;
    return 0                 if     $auth && $auth ne $hauth;
    return 0                 if     $path =~ /\.\.\//;
    return 0                 if     $path =~ /\/?index\.(?!html)\w+/;
    $scheme = $hscheme       unless $scheme;
    $path = substr($path, 1) if     $path =~ /^\/.+/;
    $path = substr($path, 2) if     $path =~ /^\.\/.+/;
    $path .= "index.html"    if     $path =~ /\/$/ && $query;
    $path = $ppath           unless $path;
    $auth = $pauth           unless $auth;
    
    return $url = uri_join($scheme, $auth, $path, $query);
}

sub mkdiff
{
    my $a = shift @_;
    my $b = shift @_;
    my $swap = shift @_;
    
    my $diff = diff $a, $b;
    my @diff_array = split /^/m, $diff;
    my @minus = grep { m/^(\-{1}(?!\-+)).+/g } @diff_array; @minus = grep { s/^\-// } @minus;
    my @plus = grep { m/^(\+{1}(?!\++)).+/g } @diff_array;  @plus = grep { s/^\+// } @plus;
    open  FILE, '>' . $b;
    print FILE @plus;
    close FILE;
    if ($swap) {
        open  FILE, '>' . $a;
        print FILE @minus;
        close FILE;
    }
}
