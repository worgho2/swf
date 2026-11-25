#!/bin/sh
# Rebuilds the fixtures of tests/framescripts from fixtures/src with the Flex
# SDK 4.16.1 mxmlc (playerglobal 32.0), uncompressed (FWS) so that reading
# them does not need lime's zlib:
#   living.swf  one DoABC: Living (frames 1 to 4) and its base ActionMovie;
#   twoabc.swf  the same plus game.later.Later in a second frame, which
#               mxmlc writes as a second DoABC tag.
set -eu
cd "$(dirname "$0")/src"
mxmlc -output=../living.swf -static-link-runtime-shared-libraries=true -debug=false -compress=false Main.as
mxmlc -output=../twoabc.swf -static-link-runtime-shared-libraries=true -debug=false -compress=false -frames.frame=two,game.later.Later Main.as
