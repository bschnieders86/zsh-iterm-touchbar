# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-+}"
GIT_UNSTAGED="${GIT_UNSTAGED:-!}"
GIT_UNTRACKED="${GIT_UNTRACKED:-?}"
GIT_STASHED="${GIT_STASHED:-$}"
GIT_UNPULLED="${GIT_UNPULLED:-⇣}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⇡}"

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

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~' '^[[1;2P'  '^[[1;2Q'  '^[[1;2R'  '^[[1;2S' '^[[15:2~'  '^[[17:2~' '^[[18:2~' '^[[19:2~')
touchBarState=''
yarnScripts=()
lastPackageJsonPath=''

 _clearTouchbar() {
  echo -ne "\033]1337;PopKeyLabels\a"
}

 _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

 _displayDefault() {
  _clearTouchbar
  _unbindTouchbar

  touchBarState=''

  # CURRENT_DIR
  # -----------
  echo -ne "\033]1337;SetKeyLabel=F1=👉 $(echo $(pwd) | awk -F/ '{print $(NF-1)"/"$(NF)}')\a"
  bindkey -s '^[OP' 'ls -la \n'

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

    echo -ne "\033]1337;SetKeyLabel=F2=🎋 $(git_current_branch)\a"
    echo -ne "\033]1337;SetKeyLabel=F3=$touchbarIndicators\a"
    echo -ne "\033]1337;SetKeyLabel=F4=✉️ push\a";

    # bind git actions
    bindkey '^[OQ' _displayBranches
    bindkey -s '^[OR' 'git status \n'
    bindkey -s '^[OS' "git push origin $(git_current_branch) \n"
  fi

  fnKeysIndex=5

  # Rails
  # ------------
  grep 'rails' 'Gemfile' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
      echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=🚂️ rails \a"
      bindkey "${fnKeys[$fnKeysIndex]}" _displayRailsOptions
      fnKeysIndex=$((fnKeysIndex + 1))
  elif test -e Rakefile ; then
      if _rake_does_task_list_need_generating; then
          echo "\nGenerating .rake_tasks..." >&2
          _rake_generate
      fi
      
      echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=⚡️ rake tasks\a"
      bindkey "${fnKeys[$fnKeysIndex]}" _displayRakeTasks
      fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # DOCKER-COMPOSE.yaml
  # ------------
  if test -e docker-compose.yaml || test -e docker-compose.yml; then
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=⚡️ docker \a"
    bindkey "${fnKeys[$fnKeysIndex]}" _displayDockerComposerOptions
    fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # PACKAGE.JSON
  # ------------
  if [[ -f package.json ]]; then
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=⚡️ yarn run\a"
    bindkey "${fnKeys[$fnKeysIndex]}" _displayYarnScripts
    fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # COMPOSER.JSON
  # ------------
  if [[ -f composer.json ]]; then
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=⚡️ composer\a"
    if [[ -f composer.lock ]]; then
      command='composer update \n'
    else
      command='composer install \n'
    fi
    bindkey -s "${fnKeys[$fnKeysIndex]}" $command
    fnKeysIndex=$((fnKeysIndex + 1))
  fi

  # phpunit.xml
  # ------------
  if [[ -f phpunit.xml ]]; then
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=⚡️ phpunit\a"
    bindkey -s "${fnKeys[$fnKeysIndex]}" "phpunit \n"
    fnKeysIndex=$((fnKeysIndex + 1))
  fi

}

 _displayYarnScripts() {
  # find available npm run scripts only if new directory
  if [[ $lastPackageJsonPath != $(echo "$(pwd)/package.json") ]]; then
    lastPackageJsonPath=$(echo "$(pwd)/package.json")
    yarnScripts=($(node -e "console.log(Object.keys($(npm run --json)).filter(name => !name.includes(':')).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 12).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='yarn'

  fnKeysIndex=1
  for yarnScript in "$yarnScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    bindkey -s $fnKeys[$fnKeysIndex] "yarn run $yarnScript \n"
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=$yarnScript\a"
  done

  echo -ne "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

 _displayBranches() {

   _clearTouchbar
   _unbindTouchbar

   touchBarState='gitCheckout'

   fnKeysIndex=1
   for branch in $(git branch); do
     if [[ $branch != "*" ]]; then
       fnKeysIndex=$((fnKeysIndex + 1))
       bindkey -s $fnKeys[$fnKeysIndex] "git checkout $branch \n"
       echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=$branch\a"
     fi
   done

   echo -ne "\033]1337;SetKeyLabel=F1=👈 back\a"
   bindkey "${fnKeys[1]}" _displayDefault
 }

_displayRakeTasks() {

    _clearTouchbar
    _unbindTouchbar

    touchBarState='rakeTasks'

    fnKeysIndex=1
    tasks=($(cat .rake_tasks |tr '\n' ' '))

    for task in $tasks; do

      fnKeysIndex=$((fnKeysIndex + 1))
      _addRakeTask $task $fnKeysIndex
    done

    echo -ne "\033]1337;SetKeyLabel=F1=👈 back\a"
    bindkey "${fnKeys[1]}" _displayDefault
  }

_addRakeTask() {
  if (($2 <= 16)); then
      bindkey -s $fnKeys[$2] "rake $task \n"
      echo -ne "\033]1337;SetKeyLabel=F$2=$task\a"
  fi
}

 _rake_does_task_list_need_generating () {
  [[ ! -f .rake_tasks ]] || [[ Rakefile -nt .rake_tasks ]] || { _is_rails_app && _tasks_changed }
}

 _is_rails_app () {
  [[ -e "bin/rails" ]] || [[ -e "script/rails" ]]
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
  tasks=(up stop down build)

  for task in $tasks; do

    fnKeysIndex=$((fnKeysIndex + 1))
    echo -ne "\033]1337;SetKeyLabel=F$fnKeysIndex=$task\a"
    bindkey -s $fnKeys[$fnKeysIndex] "docker-compose $task \n"
  done

  echo -ne "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault

}

_displayRailsOptions(){
    _clearTouchbar
    _unbindTouchbar

    touchBarState='railsOptions'

    echo -ne "\033]1337;SetKeyLabel=F2=start\a"
    bindkey -s $fnKeys[2] "bundle exec rails s \n"

    echo -ne "\033]1337;SetKeyLabel=F3=run tests\a"
    bindkey -s $fnKeys[3] "bundle exec rake test \n"

    echo -ne "\033]1337;SetKeyLabel=F4=list tasks\a"
    bindkey -s $fnKeys[4] "bundle exec rake -T \n"

    echo -ne "\033]1337;SetKeyLabel=F5=reset DB\a"
    bindkey -s $fnKeys[5] "bundle exec rake db:drop && bundle exec db:create && bundle exec db:setup \n"

    echo -ne "\033]1337;SetKeyLabel=F1=👈 back\a"
    bindkey "${fnKeys[1]}" _displayDefault
}

zle -N _displayDefault
zle -N _displayYarnScripts
zle -N _displayBranches
zle -N _displayRakeTasks
zle -N _displayRailsOptions
zle -N _displayDockerComposerOptions


precmd_iterm_touchbar() {
  if [[ $touchBarState == 'yarn' ]]; then
    _displayYarnScripts
  elif [[ $touchBarState == 'gitCheckout' ]]; then
    _displayBranches
  elif [[ $touchBarState == 'rakeTasks' ]]; then
    _displayRakeTasks
  elif [[ $touchBarState == 'dockerComposerOptions' ]]; then
    _displayDockerComposerOptions
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
