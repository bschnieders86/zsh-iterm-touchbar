# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-+}"
GIT_UNSTAGED="${GIT_UNSTAGED:-!}"
GIT_UNTRACKED="${GIT_UNTRACKED:-?}"
GIT_STASHED="${GIT_STASHED:-$}"
GIT_UNPULLED="${GIT_UNPULLED:-⇣}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⇡}"

# YARN
YARN_ENABLED=true
CURRENT_DIR_CMD='pwd'

# https://unix.stackexchange.com/a/22215
find-up () {
  path=$(pwd)
  while [[ "$path" != "" && ! -e "$path/$1" ]]; do
    path=${path%/*}
  done
  echo "$path"
}

# Output name of current branch.
git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

# Uncommitted changes.
# Check for uncommitted changes in the index.
git_uncomitted() {
  if ! $(git diff --quiet --ignore-submodules --cached); then
    echo -n "${GIT_UNCOMMITTED}"
  fi
}

# Unstaged changes.
# Check for unstaged changes.
git_unstaged() {
  if ! $(git diff-files --quiet --ignore-submodules --); then
    echo -n "${GIT_UNSTAGED}"
  fi
}

# Untracked files.
# Check for untracked files.
git_untracked() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo -n "${GIT_UNTRACKED}"
  fi
}

# Stashed changes.
# Check for stashed changes.
git_stashed() {
  if $(git rev-parse --verify refs/stash &>/dev/null); then
    echo -n "${GIT_STASHED}"
  fi
}

# Unpushed and unpulled commits.
# Get unpushed and unpulled commits from remote and draw arrows.
git_unpushed_unpulled() {
  # check if there is an upstream configured for this branch
  command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

  local count
  count="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
  # exit if the command failed
  (( !$? )) || return

  # counters are tab-separated, split on tab and store as array
  count=(${(ps:\t:)count})
  local arrows left=${count[1]} right=${count[2]}

  (( ${right:-0} > 0 )) && arrows+="${GIT_UNPULLED}"
  (( ${left:-0} > 0 )) && arrows+="${GIT_UNPUSHED}"

  [ -n $arrows ] && echo -n "${arrows}"
}

pecho() {
  if [ -n "$TMUX" ]
  then
    echo -ne "\ePtmux;\e$*\e\\"
  else
    echo -ne $*
  fi
}

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
# F13-F20: just running read and pressing F13 through F20. F21-24 don't print escape sequences
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~' '^[[1;2P' '^[[1;2Q' '^[[1;2R' '^[[1;2S' '^[[15;2~' '^[[17;2~' '^[[18;2~' '^[[19;2~')
touchBarState=''
npmScripts=()
gitBranches=()
lastPackageJsonPath=''

function _clearTouchbar() {
  pecho "\033]1337;PopKeyLabels\a"
}

function _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

function setKey(){
  pecho "\033]1337;SetKeyLabel=F${1}=${2}\a"
  if [ "$4" != "-q" ]; then
    bindkey -s $fnKeys[$1] "$3 \n"
  else
    bindkey $fnKeys[$1] $3
  fi
}

function _displayDefault() {
  _clearTouchbar
  _unbindTouchbar

  touchBarState=''

  # CURRENT_DIR
  # -----------
  local current_dir_label="👉 $(echo $(pwd) | awk -F/ '{print $(NF-1)"/"$(NF)}')\a"
  setKey 1 "$current_dir_label" "$CURRENT_DIR_CMD"

  # GIT
  # ---
  # Check if the current directory is in a Git repository.
  command git rev-parse --is-inside-work-tree &>/dev/null || return

  # Check if the current directory is in .git before running git checks.
  if [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then

    # Ensure the index is up to date.
    git update-index --really-refresh -q &>/dev/null

    # String of indicators
    local indicators=''

    indicators+="$(git_uncomitted)"
    indicators+="$(git_unstaged)"
    indicators+="$(git_untracked)"
    indicators+="$(git_stashed)"
    indicators+="$(git_unpushed_unpulled)"

    [ -n "${indicators}" ] && touchbarIndicators="🔥[${indicators}]" || touchbarIndicators="🙌";

    setKey 2 "🎋 `git_current_branch`" _displayBranches '-q'
    setKey 3 $touchbarIndicators "git status"
    setKey 4 "🔼 push" "git push origin $(git_current_branch)"
    setKey 5 "🔽 pull" "git pull origin $(git_current_branch)"
  fi

  fnKeysIndex=6

  # PACKAGE.JSON
  # ------------
  if [[ $(find-up package.json) != "" ]]; then
      if [[ $(find-up yarn.lock) != "" ]] && [[ "$YARN_ENABLED" = true ]]; then
          setKey "$fnKeysIndex" "🐱 yarn-run" _displayYarnScripts '-q'
      else
         setKey "$fnKeysIndex" "⚡️ npm-run" _displayNpmScripts '-q'
      fi
      fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # Rails
  # ------------
  grep 'rails' 'Gemfile' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
      setKey "$fnKeysIndex" "🚂️ rails" _displayRailsOptions '-q'
      fnKeysIndex=$((fnKeysIndex + 1))
  elif test -e Rakefile ; then
      if _rake_does_task_list_need_generating; then
          echo "\nGenerating .rake_tasks..." >&2
          _rake_generate
      fi
      setKey "$fnKeysIndex" "⚡️ rake tasks" _displayRakeTasks '-q'
      fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # DOCKER-COMPOSE.yaml
  # ------------
  if test -e docker-compose.yaml || test -e docker-compose.yml; then
      setKey "$fnKeysIndex" "⚡️ docker" _displayDockerComposerOptions '-q'
    fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # COMPOSER.JSON
  # ------------
  if [[ -f composer.json ]]; then

      if [[ -f composer.lock ]]; then
          local cmd fs='composer update'
      else
          local cmd='composer install'
      fi

   setKey "$fnKeysIndex" "⚡️ composer" "$cmd"
   fnKeysIndex=$((fnKeysIndex + 1))
  fi

   # phpunit.xml
   # ------------
   if [[ -f phpunit.xml ]]; then
     setKey "$fnKeysIndex" "⚡️ phpunit" "phpunit"
     fnKeysIndex=$((fnKeysIndex + 1))
    fi
}


function _displayNpmScripts() {
  # find available npm run scripts only if new directory
  if [[ $lastPackageJsonPath != $(find-up package.json) ]]; then
    lastPackageJsonPath=$(find-up package.json)
    npmScripts=($(node -e "console.log(Object.keys($(npm run --json)).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 19).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='npm'

  fnKeysIndex=1
  for npmScript in "$npmScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $npmScript "npm run $npmScript"
  done

  setKey 1 "👈 back" _displayDefault '-q'
}

function _displayYarnScripts() {
  # find available yarn run scripts only if new directory
  if [[ $lastPackageJsonPath != $(find-up package.json) ]]; then
    lastPackageJsonPath=$(find-up package.json)
    yarnScripts=($(node -e "console.log([$(yarn run --json 2>>/dev/null | tr '\n' ',')].find(line => line && line.type === 'list' && line.data && line.data.type === 'possibleCommands').data.items.sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 19).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='yarn'

  fnKeysIndex=1
  for yarnScript in "$yarnScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $yarnScript "yarn run $yarnScript"
  done

  setKey 1 "👈 back" _displayDefault '-q'
}

function _displayBranches() {
  # List of branches for current repo
  gitBranches=($(node -e "console.log('$(echo $(git branch))'.split(/[ ,]+/).toString().split(',').join(' ').toString().replace('* ', ''))"))

  _clearTouchbar
  _unbindTouchbar

  # change to github state
  touchBarState='github'

  fnKeysIndex=1
  # for each branch name, bind it to a key
  for branch in "$gitBranches[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $branch "git checkout $branch"
  done

  setKey 1 "👈 back" _displayDefault '-q'
}

_displayRakeTasks() {

    _clearTouchbar
    _unbindTouchbar

    touchBarState='rakeTasks'

    fnKeysIndex=1
    tasks=($(cat .rake_tasks |tr '\n' ' '))

    for task in $tasks; do

        fnKeysIndex=$((fnKeysIndex + 1))
        if (($2 <= 16)); then
            setKey "$fnKeysIndex" "$task" "rake $task"
        fi
      _addRakeTask $task $fnKeysIndex
    done

    setKey 1 "👈 back" _displayDefault '-q'
  }

 _rake_does_task_list_need_generating () {
  [[ ! -f .rake_tasks ]] || [[ Rakefile -nt .rake_tasks ]] || { _is_rails_app && _tasks_changed }
}

 _tasks_changed () {
  local -a files
  files=(lib/tasks lib/tasks/**/*(N))

  for file in $files; do
    if [[ "$file" -nt .rake_tasks ]]; then
      return 0
    fi
  done

  return 1
}

 _rake_generate () {
  rake --silent --tasks | cut -d " " -f 2 > .rake_tasks
}

 rake_refresh () {
  [[ -f .rake_tasks ]] && rm -f .rake_tasks

  echo "generating rake task overview..." >&2
  _rake_generate
  cat .rake_tasks
}

_displayDockerComposerOptions(){
     _clearTouchbar
     _unbindTouchbar

     touchBarState='dockerComposerOptions'

     fnKeysIndex=1
     local cmds=(up stop down build)

     for cmd in $cmds; do

         fnKeysIndex=$((fnKeysIndex + 1))
        setKey "$fnKeysIndex" $cmd "docker-compose $cmd"
     done

     setKey 1 "👈 back" _displayDefault '-q'
}

_displayRailsOptions(){
    _clearTouchbar
    _unbindTouchbar

    touchBarState='railsOptions'

    setKey 1 "👈 back" _displayDefault '-q'

    setKey 2 "start" "bundle exec rails s"
    setKey 3 "run tests" "bundle exec rake test"
    setKey 4 "list tasks" "bundle exec rake -T"
    setKey 5 "reset db" "bundle exec rake db:drop && bundle exec db:create && bundle exec db:setup \n"
}



zle -N _displayDefault
zle -N _displayNpmScripts
zle -N _displayYarnScripts
zle -N _displayBranches
zle -N _displayRakeTasks
zle -N _displayRailsOptions
zle -N _displayDockerComposerOptions

precmd_iterm_touchbar() {
  if [[ $touchBarState == 'npm' ]]; then
    _displayNpmScripts
  elif [[ $touchBarState == 'yarn' ]]; then
    _displayYarnScripts
  elif [[ $touchBarState == 'github' ]]; then
      _displayBranches
  elif [[ $touchBarState == 'dockerComposerOptions' ]]; then
      _displayDockerComposerOptions
  elif [[ $touchBarState == 'railsOptions' ]]; then
      _displayRailsOptions
  elif [[ $touchBarState == 'rakeTasks' ]]; then
      _displayRakeTasks
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
