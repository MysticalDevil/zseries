set shell := ["sh", "-eu", "-c"]

projects := "zcli ztui zlog ztmpfile ztotp"

default:
  @just --list

list-projects:
  @printf '%s\n' {{projects}}

check:
  @echo '== Markdown =='
  rumdl check README.md zcli/README.md ztui/README.md zlog/README.md ztotp/README.md ztotp/docs/*.md ztmpfile/README.md
  @echo '== zcli =='
  cd zcli && zig build && zig build test
  @echo '== ztui =='
  cd ztui && zig build && zig build test
  @echo '== zlog =='
  cd zlog && zig build && zig build test
  @echo '== ztmpfile =='
  cd ztmpfile && zig build test
  @echo '== ztotp =='
  cd ztotp && zig build test

fmt:
  @echo '== Markdown =='
  rumdl fmt README.md zcli/README.md ztui/README.md zlog/README.md ztotp/README.md ztotp/docs/*.md ztmpfile/README.md
  @echo '== Zig fmt =='
  zig fmt zcli/build.zig zcli/src/*.zig
  zig fmt ztui/build.zig ztui/src/*.zig
  zig fmt zlog/build.zig zlog/src/*.zig
  zig fmt ztmpfile/build.zig ztmpfile/src/*.zig ztmpfile/src/*/*.zig ztmpfile/src/*/*/*.zig ztmpfile/tests/*.zig
  zig fmt ztotp/build.zig ztotp/src/*.zig ztotp/src/*/*.zig ztotp/src/*/*/*.zig

clean:
  rm -rf zcli/zig-cache zcli/.zig-cache zcli/zig-out
  rm -rf ztui/zig-cache ztui/.zig-cache ztui/zig-out
  rm -rf zlog/zig-cache zlog/.zig-cache zlog/zig-out
  rm -rf ztmpfile/zig-cache ztmpfile/.zig-cache ztmpfile/zig-out
  rm -rf ztotp/zig-cache ztotp/.zig-cache ztotp/zig-out
  rm -rf ztotp/.tmp-smoke* ".tmp-smoke*"

smoke *args='':
  cd ztotp && ./scripts/smoke.sh {{args}}
