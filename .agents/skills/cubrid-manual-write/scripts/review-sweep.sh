#!/usr/bin/env bash
# review-sweep.sh <pr-number> [owner/repo] — every review comment on a PR that may still need an answer.
# GitHub keeps comments in three places; a round that reads only the inline threads misses the other two
# (PR #772: a conversation-tab request sat unanswered for five weeks).
#   1. inline threads with no reply from you (bots included: greptile threads get answers too)
#   2. conversation-tab comments by people — no threading, so read each and quote-reply the open ones
#   3. non-empty review bodies by people — same
set -eu
n="${1:?usage: $0 <pr-number> [owner/repo]}"
repo="${2:-CUBRID/cubrid-manual}"
me="$(gh api user -q .login)"

echo "== inline threads without a reply from $me"
gh api "repos/$repo/pulls/$n/comments" --paginate | jq -rs --arg me "$me" '
  add // [] | (map(select(.in_reply_to_id and .user.login == $me) | .in_reply_to_id)) as $done
  | .[] | select(.in_reply_to_id == null and .user.login != $me and (.id | IN($done[]) | not))
  | "\(.id) \(.user.login) \(.path):\(.line // .original_line) \(.body | gsub("\\s+"; " ") | .[0:90])"'

echo "== conversation tab (people)"
gh api "repos/$repo/issues/$n/comments" --paginate | jq -rs '
  add // [] | .[] | select(.user.type != "Bot")
  | "\(.id) \(.created_at) \(.user.login): \(.body | gsub("\\s+"; " ") | .[0:90])"'

echo "== review bodies (people)"
gh api "repos/$repo/pulls/$n/reviews" --paginate | jq -rs '
  add // [] | .[] | select(.body != "" and .user.type != "Bot")
  | "\(.submitted_at) \(.user.login) \(.state): \(.body | gsub("\\s+"; " ") | .[0:90])"'
