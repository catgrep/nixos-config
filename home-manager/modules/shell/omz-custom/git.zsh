# Git helpers loaded by oh-my-zsh from the custom directory.

# gsk is used for syncing a local branch with the latest main branch.
# TODO:
#   - Add input validation for $newbase
#   - Check that repo isn't dirty
gsk() {
    local name="$0"
    usage() {
        echo ""
        echo "Usage: $name <ancestor> [local_branch] [rebase_branch]"
        echo ""
        echo "Arguments:"
        echo "   -n, --dry-run:   Print the commands that would be executed and the commits"
        echo "                    that would be rebased without making any changes."
        echo ""
        echo "   <ancestor>:      The commit SHA, branch name, or tag that the local branch diverged from."
        echo "                    This defines the range of commits to be rebased (exclusive of <ancestor>)."
        echo ""
        echo "  [local_branch]:   The local branch to rebase. Defaults to the current branch."
        echo ""
        echo "  [rebase_branch]:  The branch to rebase onto (e.g., main, master, develop). If not"
        echo "                    specified, the script will attempt to use 'main' or 'master'."
        echo ""
        echo "Examples:"
        echo "  Rebase current branch from the commit before HEAD onto main:"
        echo "      $name HEAD~1"
        echo ""
        echo "  Rebase 'feature-branch' from 'develop' onto 'main':"
        echo "      $name develop feature-branch main"
        echo ""
        echo "  Rebase 'foobar' branch from 'HEAD~3' onto the default main branch:"
        echo "      $name HEAD~3 foobar"
    }

    local dryrun=false
    local ancestor=""
    local localbranch=""
    local newbase=""
    local main=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --h | --help | help)
            echo "$0: Rebase a local branch onto the latest rebase_branch, starting from a specified"
            echo "    ancestor commit."
            usage
            return
            ;;
        -n | --dry-run)
            dryrun=true
            shift
            ;;
        *)
            if [ -z "$ancestor" ]; then
                ancestor="$1"
            elif [ -z "$localbranch" ]; then
                localbranch="$1"
            elif [ -z "$newbase" ]; then
                newbase="$1"
            fi
            break
            ;;
        esac
    done

    # Check if the repository is dirty
    if ! git diff --quiet --exit-code || ! git diff --cached --quiet --exit-code; then
        echo "$0: Error: Repository is dirty. Please commit or stash your changes."
        git status --short
        return 1
    fi

    # Set default for localbranch if not provided
    if [ -z "$localbranch" ]; then
        localbranch="$(git branch --show-current)"
    fi
    # Check that $ancestor is set
    if [ -z "$ancestor" ]; then
        echo "$0: Ancestor commit to rebase from is required."
        usage
        return 1
    fi

    # Check that $localbranch is valid
    if ! git rev-parse --verify --quiet "$localbranch" >/dev/null 2>&1; then
        echo "$0: No local branch to rebase."
        echo ""
        echo "Please checkout a branch with:"
        echo "     BRANCH=\"\" git checkout -b \"\$BRANCH\" $(git rev-parse --short HEAD)"
        echo ""
        echo "Then rerun with:"
        echo "     $0 $ancestor $localbranch $newbase"
        return 1
    fi
    # Check if $ancestor is actually an ancestor of $localbranch
    if ! git merge-base --is-ancestor "${ancestor}" "${localbranch}"; then
        echo "$0: ${ancestor} is not an ancestor of ${localbranch}."
        return 1
    fi

    # Parse the actual commit hash
    ancestor="$(git rev-parse --short "${ancestor}")"
    if [ $? != 0 ]; then
        echo "$0: Revision does not exist."
        return 1
    fi
    # Update $ancestor to $ancestor~1 so cherry-picking 'A..B' won't fail
    if [ "$ancestor" = "$(git rev-parse --short "${localbranch}")" ]; then
        ancestor="$(git rev-parse --short "${ancestor}~1")"
    fi

    echo "$0: Rebasing these commits:"
    git log --oneline ${ancestor}..${localbranch}
    echo ""
    echo "$0: For sanity, commits including the one before last:"
    git log --oneline ${ancestor}~1..${localbranch}
    echo ""

    if [ ! -z "$GSK_SLEEP" ]; then
        echo "$0: Here's ${GSK_SLEEP} seconds of sleep to avoid messing up your workspace! :)"
        sleep $GSK_SLEEP
    fi

    # Fallback to master if there isn't a $newbase
    if [ -z "$newbase" ]; then
        # Attempt to checkout "master"
        if git rev-parse --verify --quiet "master" >/dev/null 2>&1; then
            main=master
        else
            # If master doesn't exist, attempt to checkout "main"
            if git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
                main=main
            else
                echo "$0: Failed to find neither master nor main branch."
                return 1
            fi
        fi
        echo "$0: Falling back to ${main}."
        newbase="$main"
    fi

    if [ "$dryrun" = true ]; then
        echo "$0: [DRY-RUN] (${localbranch} => ${newbase}) 'git checkout ${newbase}'"
        echo "$0: [DRY-RUN] (${newbase}) 'git pull'"
        echo "$0: [DRY-RUN] (cp-${localbranch} -> ${newbase}) 'git checkout -b cp-${localbranch} ${newbase}'"
        echo "$0: [DRY-RUN] (cp-${localbranch}) 'git cherry-pick ${ancestor}..${localbranch}'"
        echo "$0: [DRY-RUN] (cp-${localbranch}) 'git branch -D ${localbranch}'"
        echo "$0: [DRY-RUN] (${localbranch} -> cp-${localbranch}) 'git checkout -b ${localbranch}'"
        echo "$0: [DRY-RUN] (${localbranch}) 'git branch -D cp-${localbranch}'"
        echo ""
        echo "$0: [DRY-RUN] Rebase would be complete! :)"
        return
    fi

    # Update $newbase
    if ! git checkout "${newbase}"; then
        echo "$0: Failed to checkout ${newbase}!"
        return 1
    fi
    if ! git pull; then
        echo "$0: Failed to pull latest changes! Continuing anyway..."
    fi
    echo ""

    # Check if $localbranch is already up to date with $newbase
    if git merge-base --is-ancestor "${newbase}" "${ancestor}"; then
        echo "$0: ${ancestor}..${localbranch} is already up to date with ${newbase}."
        echo "$0: Nothing to do! :)"
        git checkout "$localbranch"
        return
    fi

    # Create temporary cherry-pick branch and cherry-pick $localbranch
    echo "$0: Rebasing ${ancestor}..${localbranch} onto ${newbase}"
    git checkout -b cp-"${localbranch}" "${newbase}"

    if ! git cherry-pick "${ancestor}..${localbranch}"; then
        echo "$0: Cherry-pick failed."
        echo "$0: To abort, run:"
        echo ""
        echo "git cherry-pick --abort"
        echo "git checkout $localbranch"
        echo "git branch -D cp-${localbranch}"
        return 1
    fi

    # Update $localbranch since we have rebased it
    git branch -D "${localbranch}"
    git checkout -b "${localbranch}"

    # Delete cherry-pick branch
    git branch -D cp-"${localbranch}"
    echo ""
    echo "$0: Rebase complete! :)"
}

# gtchk is used for confirming that the commit trailers are formatted correctly
gtchk() {
    case "$1" in
    -h | --h | --help | help)
        echo "$0: check commit trailers"
        return
        ;;
    *)
        git log -n 1 --pretty=%B | git interpret-trailers --only-trailers
        ;;
    esac
}
