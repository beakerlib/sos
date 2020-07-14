#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/sos/Library/utils
#   Description: Library with various utility functions for sos tests
#   Author: David Kutalek <dkutalek@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = sos
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

sos/utils

=head1 DESCRIPTION

Library with various utility functions for sos tests.

 - sosFakeCmd  - enqueue reversible install of given 'fake' command needed by the test

 - sosFakeFile - enqueue reversible install of given tar tree of files

 - sosFakeTree - enqueue reversible install of given tar tree of files

 - sosUnfake   - immediately uninstalls all previous fakes, if executed

 - sosReport - generate reusable sosreport with given params and namespace,
               or just return already created one if possible, ie. it has:
                 - same namespace
                 - same params
                 - same fakes

               Will execute queued fake installs before generating sosreport.
               Calls unfake after sos generation, if not exlicitely asked to not do it.

 - sosReportList - printout of present, already generated sosreports,
                    with some stats like number of reuse.

 - sosReportPurge - deletes all previously generated and stored sosreports


How it is supposed to work:

    Lib user setups fakes as needed and asks for sosreport.
Given namespace, sosreport params and queued fakes are considered -
if exactly same sosreport already exists in lib data store,
it will be reused.

    In case lib user wants to generate more different sosreports with same fakes,
he can pass optional param to sosReport to not unfake immediately.

    It is possible to list and delete all already generated sosreports.

    Fake queue is being cleared everytime library loads, so far I do not see
any scenario for multi-test queues.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 sosLog

Simply logs a message into library specific log file.

    sosLog message params

=over

=item message params

Any number of parameters to be logged. Please avoid special chars like new lines.

=back

Logs a message, returns 0 when successfull.

=cut

sosLog() {
    echo $(date '+%Y-%m-%d %H:%M %z') "$*" >> $sos_LOG
    return $?
}

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 sosFakeCmd

Enqueue reversible install of given 'fake' command needed by the test

    sosFakeCmd fake destination

=over

=item fake

File name of faked command to be installed.

=item destination

Destination file name where fake is to be installed.

=back

Adds CMD:fake:destination entry into fakelist.

Returns 0 when successfull.

=cut

sosFakeCmd() {

    [ $# -eq 2 ] || { sosLog "sosFakeCmd: bad usage"; return 1; }

    local fake=$1
    local destination=$2

    fake=$(readlink -fn $fake)
# FIXME: readlink does not work for unexistant destinations.
# use combination of pwd and basename?
#    destination=$(readlink -fn $destination)
    echo "CMD:$fake:$destination" >> $sos_FAKELIST

    sosLog "enqueued fake '$fake' as '$destination'"
}


true <<'=cut'
=pod

=head2 sosFakeFile

Enqueue reversible install of given 'fake' file needed by the test

    sosFakeFile fake destination

=over

=item fake

File name of faked file to be installed.

=item destination

Destination file name where fake is to be installed.

=back

Adds FILE:fake:destination entry into fakelist.

Returns 0 when successfull.

=cut

sosFakeFile() {

    [ $# -eq 2 ] || { sosLog "sosFakeFile: bad usage"; return 1; }

    local fake=$1
    local destination=$2

    fake=$(readlink -fn $fake)
# FIXME: readlink does not work for unexistant destinations.
# use combination of pwd and basename?
#    destination=$(readlink -fn $destination)
    echo "FILE:$fake:$destination" >> $sos_FAKELIST

    sosLog "sosFakeFile: enqueued fake '$fake' as '$destination'"
}


true <<'=cut'
=head2 sosFakeTree

Enqueue reversible install of given 'fake' tar tree of files needed by the test

    sosFakeTree fake-archive

=over

=item fake-archive

Archive with faked filesystem tree to be enqueued.
It should be extractable by tar (eg. tar.gz).
To be extracted, hopefully safely, into root (/).

=back

Adds TREE:fake-archive entry into fakelist.

Returns 0 when successfull.

=cut

sosFakeTree() {

    [ $# -eq 1 ] || { sosLog "sosFakeTree: bad usage"; return 1; }

    local fake_archive=$1

    fake_archive=$(readlink -fn $fake_archive)
    echo "TREE:$fake_archive" >> $sos_FAKELIST

    sosLog "sosFakeTree: enqueued fake archive '$fake_archive'"
}

true <<'=cut'
=head2 sosUnfake

Immediately uninstalls all previous fakes, if executed.

    sosUnfake

=over

=back

Uninstalls faked commands, files and file trees via rlFileRestore.
Clears previously created fakelist.

Returns 0 when successfull.

=cut

sosUnfake() {

    [ $# -eq 0 ] || { sosLog "sosUnfake: bad usage"; return 1; }

    echo -n '' > $sos_FAKELIST

    if rlFileRestore --namespace $sos_BACKUP_NAMESPACE; then
        sosLog "sosUnfake: fakes successfully uninstalled"
        return 0
    else
        sosLog "sosUnfake: uninstall error"
        return 1
    fi
}

true <<'=cut'
=head2 sosReport

Generates reusable sosreport with given params and namespace,
or just return already created one if possible.

    sosReport "sosreport params" [namespace] [no-unfake] [exit-value]

Notes:

 * This will execute queued fake installs before generating sosreport.
 * Calls sosUnfake after sos generation by default
 * Previously generated sosreport can be reused if all of these apply:
    * same namespace
    * same params
    * same fakes

=over

=item "sosreport params"

This is a string with parameters for sosreport itself.
It has to be formally one parameter, therefore usually quotes needed.

=item namespace

Namespace can be used to differentiate even sosreports with same args.
This can be used eg. for cases with specifically altered environment
before running sosreport. By using new namespace, you can be sure
new sosreport will be generated.

Defaults to 'default'. Do not use whitespace.

=item no-unfake

Use no-unfake keyword to not run sosUnfake after sosreport generation.
This can be usefull eg. when you need to make more different sosreports
with same fake setup.

=item exit-value

Allow sosreport to fail with different exit value than 0. Accepts the
same syntax as rlRun() so both single status or range is accepted.
Setting this to failure status does not affect the return value
of this function. So it will likely result in 20 and must be handled
in a calling script.

=back

When successfull, populates sos_REPORT with full path to valid sosreport
and returns 0.
=cut

sosReport() {

    [ $# -lt 1 ] && { sosLog "sosReport: bad usage"; return 1; }
    [ $# -gt 4 ] && { sosLog "sosReport: bad usage"; return 1; }

    local params="$1"
    local namespace="$2" ; [ "_$namespace" = "_" ] && namespace='default'
    local unfake=1
    local exitvalue="$4"; [ "_$exitvalue" = "_" ] || [ "_$exitvalue" = "_default" ] && exitvalue=0

    if [ "_$3" = "_no-unfake" ]; then
        unfake=0
    fi

    sosLog "sosReport: Tree fakes not yet implemented, will be skipped!!!"

    local fakesum=$(cat $sos_FAKELIST | grep -v '^TREE' | sha1sum | sed 's/ .*//')
    local paramsum=$(echo "$params" | tr ' ' '\n' | sort | grep -v '^\s*$' | sha1sum | sed 's/ .*//')

    local report_id="$paramsum $namespace $fakesum"

    sosLog "sosReport: was asked for <$report_id>"

    # decide whether to use older report

        # TODO: already generated sosreport detection and usage
        # - detect based on report_id and sos_DB
        # - incrementing sosreport usage count in sos_DB
        # - no fake execution, therefore also no unfake
        # - returning report


    # otherwise, lets install fakes and generate new sosreport

    local fakelist
    local IFS_backup="$IFS" ; IFS=':'
    local row

    echo "---[sos_FAKELIST]---"; cat $sos_FAKELIST; echo "---" # DEBUG
    cat $sos_FAKELIST | while read -a row; do

        if [ ${#row[@]} -lt 2 ]; then
            sosLog "sosReport: skipping wrongly formatted fake (${row[@]})"
            continue;
        fi

        # FILE:/path/to/fake:/path/to/destination
        if [ ${row[0]} = 'FILE' ]; then
            # Try to backup file with clean option to allow for nonexistent files removal
            rlFileBackup --clean --namespace $sos_BACKUP_NAMESPACE ${row[2]} || {
                sosLog "sosReport: cannot backup '${row[2]}', skipping"
                continue
            }

            # Create does not exists
            if ! [ -e "${row[2]}" ]; then
                mkdir -p $(dirname "${row[2]}")
            fi

            /bin/cp -f "${row[1]}" "${row[2]}" || {
                sosLog "sosReport: cannot install FILE fake '${row[1]}' to '${row[2]}'"
            }
            # FIXME: file fake install - something more needed besides cp?

        # CMD:/path/to/cmd:/path/to/destination
        elif [ ${row[0]} = 'CMD' ]; then
            # Try to backup file with clean option to allow for nonexistent files removal
            rlFileBackup --clean --namespace $sos_BACKUP_NAMESPACE ${row[2]} || {
                sosLog "sosReport: cannot backup '${row[2]}', skipping"
                continue
            }

            # Create if does not exists
            if [ -e "${row[2]}" ]; then
                mkdir -p $(dirname "${row[2]}")
            fi

            /bin/cp -f "${row[1]}" "${row[2]}" || {
                sosLog "sosReport: cannot install CMD fake '${row[1]}' to '${row[2]}'"
                continue
            }
            chmod a+x "${row[2]}"

        # TREE:/path/to/tree/archive
        elif [ "${row[0]}" = 'TREE' ]; then
            sosLog "sosReport: Skipping unimplemented TREE fake entry (${row[1]})"
            # TODO: implement TREE fake install
            continue

        else
            sosLog "sosReport: unknown fake type (${row[0]})"
            continue
        fi

    done

    IFS="$IFS_backup"

    # TODO: implement handling of unpacked reports generated with --build option
    # hint:  grep 'sosreport build tree is located at *:' | sed 's/^.*: //'
    echo "$params" | grep -- '--build' && {
        sosLog "sosReport: --build parameter detected but not supported yet, bailing out"
        return 10
    }

    # may need to handle rhel 5/6/7 differencies
    # would be nice to use RUNPTY if such env variable exists?
    local sos_output=$(mktemp)
    set -o pipefail
    # choose a way of running sosreport
    if echo "$params" | grep -- '--batch'; then
        local sos_cmd="sosreport $params < /dev/null 2>&1 | tee $sos_output"
    else
        local sos_cmd="echo -e '\ntester\n123\n' | sosreport $params 2>&1 | tee $sos_output"
    fi
    sosLog "sosReport: Executing \"$sos_cmd\""
    rlRun "$sos_cmd" $exitvalue "sosReport: generating new report"
    sos_REPORT=$(cat $sos_output | sed -n '/Your sosreport has been generated and saved in:/,+1p' | grep '/sosreport-.*tar.*' | sed 's/^ *//')
    [ $? = 0 ] || {
        sosLog "sosReport: Generated sosreport not recognized from sosreport output!"
        sos_REPORT=''
        return 20
    }
    sos_SUM="$sos_REPORT.md5"
    set +o pipefail

    # move the report to our library storage place
    mv "$sos_REPORT" "$sos_SUM" "$sos_STORAGE"
    sos_REPORT="$sos_STORAGE/$(basename $sos_REPORT)"
    sos_SUM="$sos_STORAGE/$(basename $sos_SUM)"
    # used to hack over rlWatchdog; rlWatchdog hack
    ln -fs "$sos_REPORT" $sos_STORAGE/lastreport

    # append new entry into our sosreport db
    echo "1 $report_id $(basename $sos_REPORT)" >> $sos_DB

    # store full additional info for this report
    /bin/cp -f "$sos_FAKELIST" "$sos_REPORT.fakelist"
    echo "$params" > "$sos_REPORT.params"
    /bin/cp -f "$sos_output" "$sos_REPORT.output"
    rlRun "tar tf $sos_REPORT | tee '$sos_REPORT.listing' |wc -l" 0 "sosReport: listing generated report"

    sosLog "sos_REPORT=$sos_REPORT"

    ls -l "$sos_REPORT"*

    # unfake if wanted
    if [ "_$unfake" = "_1" -a $(wc -l < $sos_FAKELIST) -gt 0 ]; then
        sosUnfake
    fi

    # so to not return unfake result actually, FIXME ?
    return 0
}

true <<'=cut'
=head2 sosAssertFileIncluded

Assert presence of given filename in laste generated report ($sos_REPORT.listing).

    sosAssertFileIncluded regexp

=over

=item regexp

Regular expression for matching filename, including path.

=back

Asserts and returns 0 when successfull.

=cut

sosAssertFileIncluded() {

    [ $# -eq 1 ] || { sosLog "sosAssertFileIncluded: bad usage"; return 1; }

    rlRun "grep '$1' '$sos_REPORT.listing' < /dev/null" 0 "sosAssertFileIncluded '$1'"

    return $?
}

true <<'=cut'
=head2 sosAssertFileNotIncluded

Assert absence of given filename in laste generated report ($sos_REPORT.listing).

    sosAssertFileNotIncluded regexp

=over

=item regexp

Regular expression for matching filename, including path.

=back

Asserts and returns 0 when successfull.

=cut

sosAssertFileNotIncluded() {

    [ $# -eq 1 ] || { sosLog "sosAssertFileNotIncluded: bad usage"; return 1; }

    rlRun "grep '$1' '$sos_REPORT.listing' < /dev/null" 1 "sosAssertFileNotIncluded '$1'"

    return $?
}

true <<'=cut'
=head2 sosReportList

Printout of already generated sosreports with some stats like number of reuse.

    sosReportList

=over

=back

Returns 0 when successfull.

=cut

sosReportList() {

    [ $# -eq 0 ] || { sosLog "sosReportList: bad usage"; return 1; }

    ls -l $sos_STORAGE
    cat $sos_DB

    sosLog "sosReportList: listed $(wc -l $sos_DB) already generated reports"

    return 0
}


true <<'=cut'
=head2 sosReportPurge

Deletes all previously generated and stored sosreports, cleans reports db.

    sosReportPurge

=over

=back

Returns 0 when successfull.

=cut

sosReportPurge() {

    [ $# -eq 0 ] || { sosLog "sosReportPurge: bad usage"; return 1; }

    rm -f "$sos_STORAGE/sosreport*"
    echo -n '' > $sos_DB

    sosLog "sosReportPurge: deleted all previously generated reports"

    return 0
}


sosLibraryLoaded () {

    # plugin directory
    sos_PLUGINDIR=$(rpm -ql sos | grep 'plugins/__init__.py$')
    sos_PLUGINDIR=$(dirname $sos_PLUGINDIR)

    # used for faked files backup
    sos_BACKUP_NAMESPACE='sosutils'

    # setup lib dir variable, root dir used for various storage
    sos_LIBDIR=$( readlink -fn $( dirname ${BASH_SOURCE[0]} ) )

    # fake list is meant to be temporary, always just for one test
    # note: no easy way to cleanly unfake after previous test

    sos_FAKELIST="$sos_LIBDIR/fakelist.txt"

    echo -n '' > "$sos_FAKELIST"

    # setup report storage dir variable and subdir friends;
    # storage is meant to be permanent for multiple tests,
    # until purged by sosReportPurge

    sos_STORAGE="$sos_LIBDIR/storage"
    sos_LOG="$sos_STORAGE/log.txt"
    sos_DB="$sos_STORAGE/db.txt"

    touch "$sos_LOG" > /dev/null 2>&1 || mkdir $sos_STORAGE || return 1
    touch "$sos_DB"

    local details="${TEST:-user}"
    sosLog '---'
    sosLog "library loaded by: $details"

    # FIXME: only with DEBUG?
    rlRun "set | grep '^sos_.*'" 0 "sos/utils library loaded, variables defined"

    return 0
}
