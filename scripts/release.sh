#!/bin/bash
#
# Name::        release.sh
# Description:: Use this script to prepare a new release on Github,
#               the automation will create a GH tag like 'v0.1.0'
#               (using the VERSION file)
# Author::      Salim Afiune Maya (<afiune@lacework.net>)
#
set -eou pipefail

readonly org_name=lacework
readonly project_name=terraform-kubernetes-agent
readonly git_user="Lacework Inc."
readonly git_email="ops+releng@lacework.net"
VERSION=$(cat VERSION)

usage() {
  local _cmd
  _cmd="$(basename "${0}")"
  cat <<USAGE
${_cmd}: A tool that helps you do releases!

Use this script to prepare a new Github release, the automation will generate
release notes, update the changelog and create a Github tag like 'v0.1.0'.

USAGE:
    ${_cmd} [command]

COMMANDS:
    prepare    Generates release notes, updates version and CHANGELOG.md
    verify     Check if the release is ready to be applied
    trigger    Trigger a release by creating a git tag
    publish    Creates a Github tag like 'v0.1.0'
USAGE
}

main() {
  case "${1:-}" in
    prepare)
      prepare_release
      ;;
    publish)
      publish_release
      ;;
    verify)
      verify_release
      ;;
    trigger)
      trigger_release
      ;;
    *)
      usage
      ;;
  esac
}

trigger_release() {
  if [[ "$VERSION" =~ "-dev" ]]; then
      log "No release needed. (VERSION=${VERSION})"
      log ""
      log "Read more about the release process at:"
      log "  - https://github.com/${org_name}/${project_name}/wiki/Release-Process"
    else
      log "VERSION ready to be released to 'x.y.z' tag. Triggering a release!"
      log ""
      tag_release
      bump_version
  fi
}

verify_release() {
  log "verifying new release"
  _changed_file=$(git whatchanged --name-only --pretty="" origin..HEAD)
  _required_files_for_release=(
    RELEASE_NOTES.md
    CHANGELOG.md
    VERSION
  )
  for f in "${_required_files_for_release[@]}"; do
    if [[ "$_changed_file" =~ "$f" ]]; then
      log "(required) '$f' has been modified. Great!"
    else
      warn "$f needs to be updated"
      warn ""
      warn "Read more about the release process at:"
      warn "  - https://github.com/${org_name}/${project_name}/wiki/Release-Process"
      exit 123
    fi
  done

  if [[ "$VERSION" =~ "-dev" ]]; then
      warn "the 'VERSION' needs to be cleaned up to be only 'x.y.z' tag"
      warn ""
      warn "Read more about the release process at:"
      warn "  - https://github.com/${org_name}/${project_name}/wiki/Release-Process"
      exit 123
    else
      log "(required) VERSION has been cleaned up to 'x.y.z' tag. Great!"
  fi
}

prepare_release() {
  log "preparing new release"
  prerequisites
  remove_tag_version
  generate_release_notes
  update_changelog
  push_release
}

publish_release() {
  log "releasing v$VERSION"
  create_release
}

update_changelog() {
  log "updating CHANGELOG.md"
  _changelog=$(cat CHANGELOG.md)
  echo "# v$VERSION" > CHANGELOG.md
  echo "" >> CHANGELOG.md
  echo "$(cat CHANGES.md)" >> CHANGELOG.md
  echo "---" >> CHANGELOG.md
  echo "$_changelog" >> CHANGELOG.md
  # clean changes file since we don't need it anymore
  rm CHANGES.md
}

load_list_of_changes() {
  latest_version=$(find_latest_version)
  local _list_of_changes=$(git log --no-merges --pretty="* %s (%an)([%h](https://github.com/${org_name}/${project_name}/commit/%H))" ${latest_version}..main)

  # init changes file
  true > CHANGES.md

  _feat=$(echo "$_list_of_changes" | grep "\* feat[:(]")
  _refactor=$(echo "$_list_of_changes" | grep "\* refactor[:(]")
  _perf=$(echo "$_list_of_changes" | grep "\* perf[:(]")
  _fix=$(echo "$_list_of_changes" | grep "\* fix[:(]")
  _doc=$(echo "$_list_of_changes" | grep "\* doc[:(]")
  _docs=$(echo "$_list_of_changes" | grep "\* docs[:(]")
  _style=$(echo "$_list_of_changes" | grep "\* style[:(]")
  _chore=$(echo "$_list_of_changes" | grep "\* chore[:(]")
  _build=$(echo "$_list_of_changes" | grep "\* build[:(]")
  _ci=$(echo "$_list_of_changes" | grep "\* ci[:(]")
  _test=$(echo "$_list_of_changes" | grep "\* test[:(]")

  if [ "$_feat" != "" ]; then
    echo "## Features" >> CHANGES.md
    echo "$_feat" >> CHANGES.md
  fi

  if [ "$_refactor" != "" ]; then
    echo "## Refactor" >> CHANGES.md
    echo "$_refactor" >> CHANGES.md
  fi

  if [ "$_perf" != "" ]; then
    echo "## Performance Improvements" >> CHANGES.md
    echo "$_perf" >> CHANGES.md
  fi

  if [ "$_fix" != "" ]; then
    echo "## Bug Fixes" >> CHANGES.md
    echo "$_fix" >> CHANGES.md
  fi

  if [ "${_docs}${_doc}" != "" ]; then
    echo "## Documentation Updates" >> CHANGES.md
    if [ "$_doc" != "" ]; then echo "$_doc" >> CHANGES.md; fi
    if [ "$_docs" != "" ]; then echo "$_docs" >> CHANGES.md; fi
  fi

  if [ "${_style}${_chore}${_build}${_ci}${_test}" != "" ]; then
    echo "## Other Changes" >> CHANGES.md
    if [ "$_style" != "" ]; then echo "$_style" >> CHANGES.md; fi
    if [ "$_chore" != "" ]; then echo "$_chore" >> CHANGES.md; fi
    if [ "$_build" != "" ]; then echo "$_build" >> CHANGES.md; fi
    if [ "$_ci" != "" ]; then echo "$_ci" >> CHANGES.md; fi
    if [ "$_test" != "" ]; then echo "$_test" >> CHANGES.md; fi
  fi
}

generate_release_notes() {
  log "generating release notes at RELEASE_NOTES.md"
  load_list_of_changes
  echo "# Release Notes" > RELEASE_NOTES.md
  echo "Another day, another release. These are the release notes for the version \`v$VERSION\`." >> RELEASE_NOTES.md
  echo "" >> RELEASE_NOTES.md
  echo "$(cat CHANGES.md)" >> RELEASE_NOTES.md
}

push_release() {
  log "commiting and pushing the release to github"
  git checkout -B release
  git commit -am "Release v$VERSION"
  git push origin release
  log ""
  log "Follow the above url and open a pull request"
}

tag_release() {
  local _tag="v$VERSION"
  log "creating github tag: $_tag"
  git tag "$_tag"
  git push origin "$_tag"
}

prerequisites() {
  local _branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "$_branch" != "main" ]; then
    warn "Releases must be generated from the 'main' branch. (current $_branch)"
    warn "Switch to the main branch and try again."
    exit 127
  fi

  local _unsaved_changes=$(git status -s)
  if [ "$_unsaved_changes" != "" ]; then
    warn "You have unsaved changes in the main branch. Are you resuming a release?"
    warn "To resume a release you have to start over, to remove all unsaved changes run the command:"
    warn "  git reset --hard origin/main"
    exit 127
  fi
}

find_latest_version() {
  local _pattern="v[0-9]\+.[0-9]\+.[0-9]\+"
  local _versions
  _versions=$(git ls-remote --tags --quiet | grep $_pattern | tr '/' ' ' | awk '{print $NF}')
  echo "$_versions" | tr '.' ' ' | sort -nr -k 1 -k 2 -k 3 | tr ' ' '.' | head -1
}

remove_tag_version() {
  echo $VERSION | awk -F. '{printf("%d.%d.%d", $1, $2, $3)}' > VERSION
  VERSION=$(cat VERSION)
  log "updated version to v$VERSION"
}

bump_version() {
  log "updating version after tagging release"
  latest_version=$(find_latest_version)

  if [[ "v$VERSION" == "$latest_version" ]]; then
    case "${1:-}" in
      major)
        echo $VERSION | awk -F. '{printf("%d.%d.%d-dev", $1+1, $2, $3)}' > VERSION
        ;;
      minor)
        echo $VERSION | awk -F. '{printf("%d.%d.%d-dev", $1, $2+1, $3)}' > VERSION
        ;;
      *)
        echo $VERSION | awk -F. '{printf("%d.%d.%d-dev", $1, $2, $3+1)}' > VERSION
        ;;
    esac
    VERSION=$(cat VERSION)
    log "version bumped from $latest_version to v$VERSION"
  else
    log "skipping version bump. Already bumped to v$VERSION"
    return
  fi

  log "commiting and pushing the version bump to github"
  git config --global user.email $git_email 
  git config --global user.name $git_user
  git add VERSION
  git commit -m "version bump to v$VERSION"
  git push origin main
}

create_release() {
  local _tag
  _tag=$(git describe --tags)
  local _body="/tmp/release.json"

  log "generating GH release $_tag"
  generate_release_body "$_body"
  curl -XPOST -H "Authorization: token $GITHUB_TOKEN" --data  "@$_body" \
        https://api.github.com/repos/${org_name}/${project_name}/releases

  log "the release has been completed!"
  log ""
  log " -> https://github.com/${org_name}/${project_name}/releases/tag/${_tag}"
}

generate_release_body() {
  _file=${1:-release.json}
  _tag=$(git describe --tags)
  _release_notes=$(jq -aRs .  <<< cat RELEASE_NOTES.md)
  cat <<EOF > $_file
{
  "tag_name": "$_tag",
  "name": "$_tag",
  "draft": false,
  "prerelease": false,
  "body": $_release_notes
}
EOF
}

log() {
  echo "--> ${project_name}: $1"
}

warn() {
  echo "xxx ${project_name}: $1" >&2
}

main "$@" || exit 99
