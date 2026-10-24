#!/usr/bin/env bash
# A file-write cue fires when a call adds the governed text to a governed file, by any
# tool, and stays silent for every near miss: reading the file, deleting the text, an
# edit next to text that was already there, a lookalike path. Each case is one of the
# traps in skills/context-cue/trigger-design.md.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
H="$CUES/typescript-comments.sh"

# --- must fire: the governed act, done every way it can be done ---
check FIRED "$H" "add a comment to foo.ts"        '{"session_id":"a1","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"const a=1","new_string":"// why\nconst a=1"}}'
check FIRED "$H" "Write App.tsx with /* */"       '{"session_id":"a2","tool_name":"Write","tool_input":{"file_path":"/p/App.tsx","content":"/* header */\nexport const A=1\n"}}'
check FIRED "$H" "MultiEdit, comment in .ts edit" '{"session_id":"a3","tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"/p/x.py","new_string":"x=1"},{"file_path":"/p/y.ts","new_string":"// note\nconst y=2"}]}}'
check FIRED "$H" "bash heredoc, commented .ts"    '{"session_id":"a4","tool_name":"Bash","tool_input":{"command":"cat > src/foo.ts <<EOF\n// why\nconst a=1\nEOF"}}'
check FIRED "$H" "reword an existing comment"     '{"session_id":"a5","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"// old\nconst a=1","new_string":"// new\nconst a=1"}}'
check FIRED "$H" "bash tee into a .ts file"       '{"session_id":"a6","tool_name":"Bash","tool_input":{"command":"printf \"// why\\n\" | tee -a src/foo.ts"}}'
check FIRED "$H" "bash sed -i on a .ts file"      '{"session_id":"a7","tool_name":"Bash","tool_input":{"command":"sed -i \"1i // why\" src/foo.ts"}}'

# --- trap 3: near, but not touching ---
check silent "$H" "edit line below a kept comment" '{"session_id":"b1","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"// keep\nconst a=1","new_string":"// keep\nconst a=2"}}'
# --- trap 2: the inverse of the act ---
check silent "$H" "DELETE a comment"               '{"session_id":"b2","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"// stale\nconst a=1","new_string":"const a=1"}}'
# --- trap 4: right file, act absent ---
check silent "$H" "Write foo.ts, no comments"      '{"session_id":"b3","tool_name":"Write","tool_input":{"file_path":"/p/foo.ts","content":"export const a=1\n"}}'
# --- trap 1: the match lives only in tool_response, or the file is only read ---
check silent "$H" "grep -rn // src"                '{"session_id":"b4","tool_name":"Bash","tool_input":{"command":"grep -rn \"//\" src/"},"tool_response":{"stdout":"src/foo.ts:12: // x\n"}}'
check silent "$H" "ls -la src//"                   '{"session_id":"b5","tool_name":"Bash","tool_input":{"command":"ls -la src//"},"tool_response":{"stdout":"foo.ts\n"}}'
check silent "$H" "grep foo.ts > out.txt"          '{"session_id":"b6","tool_name":"Bash","tool_input":{"command":"grep \"//\" src/foo.ts > /tmp/o.txt"}}'
check silent "$H" "a command named like tee"       '{"session_id":"b9","tool_name":"Bash","tool_input":{"command":"mytee // src/foo.ts"}}'
# --- path-token anchoring, and a near miss on the content regex ---
check silent "$H" "Edit foo.ts.snap"               '{"session_id":"b7","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts.snap","new_string":"// x"}}'
check silent "$H" "https:// is not a comment"      '{"session_id":"b8","tool_name":"Write","tool_input":{"file_path":"/p/u.ts","content":"const u=\"https://x.dev\"\n"}}'

# --- once per session ---
check FIRED  "$H" "first comment in a session"     '{"session_id":"c1","tool_name":"Write","tool_input":{"file_path":"/p/a.ts","content":"// one\n"}}'
check silent "$H" "second comment, same session"   '{"session_id":"c1","tool_name":"Write","tool_input":{"file_path":"/p/b.ts","content":"// two\n"}}'

finish file-cue-test
