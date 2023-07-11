/*
    processmail.c

    Accepts stdin and extra command-line arguments, and passes them to
    specified script, which will run as specified user.
    Must be invoked as compiled-in mail user 'MTA_USER'.

    processmail --user <user> --script <script> <args>

    Author: Dennis McRitchie

    # Based on run_email2trac by Bas van der Vlies, Walter de Jong and Michel Jouvin
    # Original copyright (C) 2002
    #
    # This program is free software; you can redistribute it and/or modify it
    # under the terms of the GNU General Public License as published by the
    # Free Software Foundation; either version 2, or (at your option) any
    # later version.
    #
    # This program is distributed in the hope that it will be useful,
    # but WITHOUT ANY WARRANTY; without even the implied warranty of
    # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    # GNU General Public License for more details.
    #
    # You should have received a copy of the GNU General Public License
    # along with this program; if not, write to the Free Software
    # Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA
 */

/* User the MTA must be running as */
#ifndef MTA_USER
#define MTA_USER "mail"
#endif

#ifndef DEBUG
#define DEBUG 0
#endif

/* Define to 1 if you have the `initgroups' function. */
#ifndef HAVE_INITGROUPS
#define HAVE_INITGROUPS 0
#endif

#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/stat.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <libgen.h>
#if HAVE_INITGROUPS
#include <grp.h>
#endif

void usage(char *prog) {
    if ( DEBUG ) printf("Usage: %s --user <effective_user> --umask <effective_umask> --script <target_script> <args> ...\n", prog);
}

int main(int argc, char** argv) {

    int i,j;
    int status;

    char *euser = NULL;
    int eumask = 0;
    char *script = NULL;
    char   **script_args;
    struct stat script_attrs;

    struct passwd *MTA;
    struct passwd *EUSER; 

    /* First copy arguments passed to the wrapper as scripts arguments
       after filtering out the wrapper options */
    if (argc < 5) {
        usage(argv[0]);
        return -1;
    }
    script_args = (char**) malloc((argc+1)*sizeof(char*));
    if (script_args == NULL) {
        if ( DEBUG ) printf("malloc failed\n");
        return 1;
    }
    j = 1;
    for (i = 1; i < argc; i++) {
        // Check for new effective user argument pair
        if (strcmp(argv[i], "--user") == 0) {
            euser = argv[++i];
        }
        // Check for new effective umask argument pair
        if (strcmp(argv[i], "--umask") == 0) {
            eumask = strtoul(argv[++i], NULL, 8);
        }
        // Check for target script path argument pair
        else if (strcmp(argv[i], "--script") == 0) {
            script = argv[++i];
        }
        // Collect the rest of the arguments
        else {
            script_args[j++] = argv[i];
        }
    }
    script_args[j] = NULL;

    // Check for mandatory arguments
    if (euser == NULL) {
        usage(argv[0]);
        return 2;
    }
    if (eumask == 0) {
        usage(argv[0]);
        return 3;
    }
    if (script == NULL) {
        usage(argv[0]);
        return 4;
    }
    script_args[0] = script;

    /* Check whether caller's uid matches that of the compiled-in MTA user */
    MTA = getpwnam(MTA_USER);
    if ( MTA == NULL ) {
        if ( DEBUG ) printf("%s compiled with non-existent MTA user (%s)\n", 
                argv[0], MTA_USER);
        return 5;
    }
    int caller = getuid();
    if ( caller !=  MTA->pw_uid ) {
        if ( DEBUG ) printf(
                "Caller UID (%d) does not match that of expected MTA user (%s)\n", 
                caller, MTA_USER);
        return 6;
    }

    // Check effective user
    EUSER = getpwnam(euser);
    if ( EUSER == NULL ) {
        if ( DEBUG ) printf("Non-existent effective user (%s) specified\n", euser);
        return 7;
    }
    // Don't allow root as an effective user
    if ( EUSER->pw_uid == 0 ) {
        if ( DEBUG ) printf("Invalid effective user (%s) specified\n", euser);
        return 8;
    }

    /* set UID, GID and supplementary groups to be those of the specified user */
#if HAVE_INITGROUPS
    if (initgroups(euser, EUSER->pw_gid)) {
        if ( DEBUG ) printf("Can't set supplementary groups for effective user (%s)\n",
                euser);
        return 9;
    }
#endif
    if (setgid(EUSER->pw_gid)) {
        if ( DEBUG ) printf("setgid failed for effective user\n");
        return 10;
    }
    if (setuid(EUSER->pw_uid)) {
        if ( DEBUG ) printf("setuid failed for effective user\n");
        return 11;
    }
    // Change effective umask
    umask(eumask);

    /* Check that target script exists */
    if ( stat(script, &script_attrs) ) {
        if ( DEBUG ) printf("Target script does not exist (%s)\n",script);
        return 12;
    }

    /* Execute script */
    status = execv(script, script_args);

    // Should never get here
    if ( DEBUG ) printf("Script (%s) execution failure (error=%d). "
            "Check permission and interpreter path.\n", script, status);
    return 13;
}
