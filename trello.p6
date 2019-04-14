#!/usr/bin/env perl6
#
# create or update cards in a Trello board from a JSON file
#
# the default listid is for the CFP list on the DevOpsDays Sthlm Speakers board
#
# to download a JSON file for DevOpsDays Sthlm from Papercall, open
# https://www.papercall.io/cfps/1986/submissions/download in a web
# browser if you've got admin access to that Papercall event
#
# prerequisites are perl6, JSON::Tiny and api keys from https://trello.com/app-key
# in debian (unstable): `apt install perl6 perl6-zef; zef install JSON::Tiny`
# or install from https://rakudo.org/files
#

use JSON::Tiny;
use HTTP::UserAgent;

my %*SUB-MAIN-OPTS = :named-anywhere;
subset NonEmptyStr of Str where * ne '';
my $cardsURL = "https://api.trello.com/1/cards";
my $ua = HTTP::UserAgent.new;

sub MAIN(
    Str $infile where *.IO.f,
    NonEmptyStr :t(:$token)!,
    NonEmptyStr :a(:$apikey)!,
    Str :l(:$listid) = "5c811f27be32a548e9ba436b",
    Bool :u(:$update) = False,
    Bool :d(:$dryrun) = False,
    Str :p(:$pattern) = '',
) {
    my @getCards = 'curl', '-s', "https://api.trello.com/1/list/$listid/cards?key=$apikey&token=$token";
    my $getCards = run @getCards, :out;
    my $existing = from-json($getCards.out.lines);
    my %ids;
    for @$existing -> %cfp {
        my $title = %cfp<name>;
        die "duplicate title '$title' in existing data" if %ids{$title};
        %ids{$title} = '/' ~ %cfp<id>;
    }
    my @getList = 'curl', '-s', "https://api.trello.com/1/list/$listid?key=$apikey&token=$token";
    my $getList = run @getList, :out;
    my $boardid = from-json($getList.out.lines)<idBoard>;

    my @getLabels = 'curl', '-s', "https://api.trello.com/1/boards/$boardid/labels?key=$apikey&token=$token";
    my $getLabels = run @getLabels, :out;
    my $labels = from-json($getLabels.out.lines);
    my %labels;
    for @$labels -> $label {
        my $name = $label<name> || next;
        $name ~~ /^ (\d+)/;
        %labels{$0} = $label<id> if $0;
    }

    my $data = from-json(slurp $infile);
    my %new;
    for @$data -> %cfp {
        my $title = %cfp<title>;
        if $pattern {
            $title ~~ /$pattern/ or next;
        }
        if %new{$title}++ {
            say "ignoring duplicate title '$title' in input data";
            next;
        }
        my $author = %cfp<name>;
        my $email = %cfp<email>;
        my $organization = %cfp<organization>;
        my $location = %cfp<location>;
        my $abstract = %cfp<abstract>;
        my $description = %cfp<description>;
        my $notes = %cfp<notes>;
        my $bio = %cfp<bio>;
        my $format = %cfp<talk_format>;
        my $tags = %cfp<tags>.join(", ");
        $format ~~ /(\d+)/;
        my $labelId = %labels{$0} // '';

        $title ~~ s/ \s+ $ //;
        $organization ~= " - $location" unless $location eq "Unknown";
        my $cardid = %ids{$title};

        my $cfp = qq:to/END/;
        *By: $author - $format*
        ### Tags
        $tags
        ### Abstract
        $abstract
        ### Description
        $description
        ### Notes
        $notes
        ### $author <<$email>>
        *$organization*

        $bio
        END
        $cfp ~~ s:g/\n/\n/; # remove \r
        $cfp ~~ s/ \s+ $ //; # remove trailing whitespace

        my $params = {
            key => $apikey,
            token => $token,
            idList => $listid,
            idLabels => $labelId,
            name => $title,
            desc => $cfp,
        };

        if $cardid {
            next unless $update;
            request("PUT", "$cardsURL$cardid", $params, $dryrun);
        } else {
            request("POST", $cardsURL, $params, $dryrun);
        }
    }
}

sub request($method, $url, $params, $dryrun) {
    my $title = %$params<name>;
    my $label = %$params<idLabels>;
    if $dryrun {
        say "$method $url $label $title";
        return;
    }

    my $response;
    if $method eq 'PUT' {
        say "Updating '$title'";
        $response = $ua.put($url, $params);
    } else {
        say "Creating '$title'";
        $response = $ua.post($url, $params);
    }
    say $response.code;
}
