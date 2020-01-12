#!/usr/bin/perl

# Workflow states:
#   UNPROCESSED
#   PROCESSING
#   SIDELINED
#   SUBJECT_UNKNOWN
#   DATE_UNKNOWN
#   PROCESSED

my $MATCH_BAR = 0.3;

use strict;
use Text::Levenshtein qw(distance);
use Date::Parse;
#use Term::Prompt;
use Time::localtime;

continuous_process();

sub continuous_process {
    print "Starting continuous process\n";
    my $waiting = 0;
    while (1) {
        my $next_pdf = next_pdf();
        if ($next_pdf) {
            $waiting = 0;
            print "\nProcessing $next_pdf\n";
            sleep 60;
            #process($next_pdf);
            readpdf($next_pdf);
        } elsif ($waiting) {
            print "."; $|++;
            sleep 60;
        } else {
            $waiting = 1;
            print "Waiting"; $|++;
            sleep 60;
        }
    }
}

sub readpdf {
    my ($filename) = @_;
    transition("unprocessed", $filename, "processing", $filename);
    system("~/scripts/readpdf \"processing/$filename\" > processing/$filename.txt") == 0
        or die "Error reading pdf";
    my $new_filename = today() . "-" . rand_id() . ".pdf";
    duplicate("processing", $filename, "evernote", $new_filename);
    transition("processing", $filename, "indexed", "en-".$new_filename);
    transition("processing", $filename.".txt", "indexed", "en-".$new_filename.".txt");    
}

sub next_pdf {
    opendir my($dh), "./unprocessed" or die "Couldn't open directory unprocessed: $!";
    my @files = readdir $dh;
    closedir $dh;
    foreach (@files) {
        if ($_ =~ /\.pdf$/) {
            return $_;
        }
    }
    return undef;
}

sub process {
    my ($filename) = @_;
    transition("unprocessed", $filename, "processing", $filename);
    my $full_text = clean(ocr("processing/$filename"));
    my $date = today(); #find_date($full_text);
    unless ($date) {
        print "I couldn't find a date.\n";
        my $choice = &prompt("y", "Do you want to enter a date?", "y/n", "y");
        if ($choice) {
            $date = &prompt("e", "Enter date:", "yymmdd", "default", '^\d{6}$');
        } else {
            transition("processing", $filename, "date_unknown", $filename);
            return;
        }
    }
    my $subject = find_subject(sample($full_text), subjects());
    unless ($subject) {
        print "I couldn't find a subject.\n";
        my $choice = &prompt("y", "Do you want to enter a subject?", "y/n", "y");
        if ($choice) {
            $subject = &prompt("e", "Enter subject:", "alpha-numeric and spaces", "", '^[\w ]+$');
            my $choice = &prompt("y", "Do you want to remember that subject for documents like this?", "Y/n", "y");
            if ($choice) {
                remember_subject($subject, $full_text);
            }
        } else {
            transition("processing", $filename, "subject_unknown", $filename);
            return;
        }
    }
    transition("processing", $filename, "processed", "$date $subject.pdf");
}

sub today {
    my $time = localtime;
    my ($day, $month, $year, $hour, $minute) = ($time->mday, $time->mon, $time->year, $time->hour, $time->min);
    my $date = sprintf("%.2d%.2d%.2d-%.2d%.2d", $year-100, $month+1, $day, $hour, $minute);
    return $date;
}

sub duplicate {
    my ($from_state, $from_filename, $to_state, $to_filename) = @_;
    if (-e "$to_state/$to_filename") {
        die "Unable to duplicate because file $to_filename already exists.";
    }
    system("cp $from_state/$from_filename \"$to_state/$to_filename\"") == 0
        or die "Failed to duplicate \"$from_filename\" to \"$to_state\" state";
    print "Duplicated \"$from_filename\" from \"$from_state\" to \"$to_state\" as \"$to_filename\"\n";
}

sub transition {
    my ($from_state, $from_filename, $to_state, $to_filename) = @_;
    if (-e "$to_state/$to_filename") {
        $to_filename = rand_id() . ".pdf";
        $to_state = "sidelined";
        print "Sidelining \"$from_filename\" because duplicate \"$to_filename\" detected\n";
    }
    system("mv $from_state/$from_filename \"$to_state/$to_filename\"") == 0
        or die "Failed to transition \"$from_filename\" to \"$to_state\" state";
    print "Transitioned \"$from_filename\" from \"$from_state\" to \"$to_state\" as \"$to_filename\"\n";
}

sub remember_subject {
    my ($subject, $full_text) = @_;
    my $filename = $subject . '.' . rand_id();
    open FILE, ">subjects/$filename" or die "Couldn't create file \"subjects/$filename\"";
    print FILE $full_text;
    close FILE;
}

sub find_subject {
    my ($target, $subjects) = @_;
    my $sample = sample($target);
    my $subject = undef;
    my $max_similarity = 0;
    foreach (keys %$subjects) {
        my $similarity = similarity($sample, $subjects->{$_});
        if ($similarity > $MATCH_BAR && $similarity > $max_similarity) {
            $subject = $_;
            $max_similarity = $similarity;
        }
    }
    if ($subject) { 
        $subject =~ s/\.\d+$//;
        print "Matched subject of \"$subject\" with $max_similarity certainty\n"; 
    }
    return $subject;
}

sub subjects {
    my @subject_files = `ls -1 ./subjects`;
    my $subjects = {};
    foreach my $key (@subject_files) {
        $key =~ s/\n//g;
        $subjects->{$key} = sample(load("subjects/$key"));
    }
    return $subjects;
}

sub ocr {
    my ($filename) = @_;
    my $tempfile = rand_id();
    print "Temp file: $tempfile\n";
    open FILE, $filename or die "Couldn't open \"$filename\"";
    system("convert -depth 8 -density 300 +matte $filename /tmp/$tempfile.tif") == 0
        or die "Convert \"$filename\" failed";
    system("tesseract /tmp/$tempfile.tif /tmp/$tempfile") == 0
        or die "OCR $filename failed";
    open FILE, "/tmp/$tempfile.txt" or die "Couldn't open \"/tmp/$tempfile.txt\"";
    local $/ = undef;
    my $ocr = <FILE>;
    close FILE;
    system("rm /tmp/$tempfile.tif") == 0
        or die "Cleanup of \"/tmp/$tempfile.tif\" failed";
    system("rm /tmp/$tempfile.txt") == 0
        or die "Cleanup of \"/tmp/$tempfile.txt\" failed";
    return $ocr;
}

sub load {
    my ($filename) = @_;
    open FILE, $filename or die "Couldn't open \"$filename\"";
    local $/ = undef;
    my $contents = <FILE>;
    close FILE;
    return $contents;
}

sub clean {
    my ($string) = @_;
    $string =~ s/[^\w\s\-\(\)\[\]\/]//g;
    return $string;
}

sub sample {
    my ($string) = @_;
    my $sample = substr $string, 0, 200;
    return $sample;
}

sub find_date {
    my ($string) = @_;
    $string =~ s/I/1/g;
    $string =~ s/O/0/g;
    my $date_string = undef;
    if ($string =~ /(\d{1,2}\/\d{1,2}\/\d{2,4})/) {
        $date_string = $1;
    } elsif ($string =~ /([A-Z]{3} \d{2} \d{2})/) {
        $date_string = $1;
    }
    if ($date_string) { 
        my $date = parse_date($date_string);
        if ($date) { print "Found date of \"$date\"\n"; }
        return $date;
    }
    else { return undef; }
}

sub parse_date {
    my ($date_string) = @_;
    my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($date_string);
    if ($year && $month && $day) {
        my $date = sprintf("%.2d%.2d%.2d", $year, $month, $day);
        return $date;
    } else {
        return undef;
    }
}

sub similarity {
    my ($a, $b) = @_;
    my $distance = distance($a, $b);
    my $max = length($a) > length($b) ? length($a) : length($b);
    my $similarity = 1 - $distance / $max;
    return $similarity;
}

sub rand_id {
    return int(rand(1000000000000));
}

