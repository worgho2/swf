import openfl.utils.ByteArray;
import swf.SWFRoot;
import swf.exporters.FrameScriptParser;

/**
	The frame script translator (FrameScriptParser, what OpenFL HTML5 runs for
	the frameN methods of a SWF class) against SWFs compiled by mxmlc
	(fixtures/build.sh), in the shapes the DDTank asset SWFs have.

	Neko, without lime's CFFI (the fixtures are uncompressed):
		cd tests/framescripts && haxe build.hxml && neko framescripts-test.n
**/
class FrameScriptsTest
{
	static var failures = 0;
	static var checks = 0;

	static function main()
	{
		var living = load("fixtures/living.swf");
		var twoabc = load("fixtures/twoabc.swf");

		// 1. A method of the base class defined in the SWF itself: Flash CS and
		// mxmlc name the protected sendCommand of ActionMovie by a QName in its
		// protected namespace, "road.game.resource:ActionMovie".
		var scripts = FrameScriptParser.convertToJS(living, "game.living.Living");
		equals("base class method", '\nthis.sendCommand("effect");', scripts[0]);

		// 2. Object literals (newobject), nested too.
		equals("object literal", '\nthis.sendCommand("focus", {"x": 0, "y": 0, "strategy": "shockingLinear", "speed": 20});', scripts[1]);
		equals("nested object literal", '\nthis.sendCommand("focus", {"x": -200, "strategy": "default", "inner": {"a": 1}});\nthis.stop();', scripts[2]);

		// 3. Every DoABC tag is read, not only the last one: Living is in the
		// first, Later in the second (mxmlc -frames, fixtures/build.sh).
		var first = FrameScriptParser.convertToJS(twoabc, "game.living.Living");
		equals("class of the first DoABC", '\nthis.sendCommand("effect");', first == null ? null : first[0]);
		var second = FrameScriptParser.convertToJS(twoabc, "game.later.Later");
		equals("class of the second DoABC", '\nthis.gotoAndPlay("later");', second == null ? null : second[0]);
		equals("base class from the first DoABC", "road.game.resource.ActionMovie", FrameScriptParser.getBaseClassName(twoabc, "game.living.Living"));
		var names = twoabc.abcClassNames();
		names.sort(Reflect.compare);
		equals("classes of every DoABC", "Main,game.later.Later,game.living.Living,road.game.resource.ActionMovie", names.join(","));
		equals("one block per DoABC", 2, twoabc.abcBlocks.length);

		Sys.println('$checks checks, $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function load(path:String):SWFRoot
	{
		return new SWFRoot(ByteArray.fromBytes(sys.io.File.getBytes(path)));
	}

	static function equals(what:String, want:Dynamic, got:Dynamic)
	{
		checks++;
		if (want != got)
		{
			failures++;
			Sys.println('FAIL $what\n  want: ' + Std.string(want).split("\n").join("\\n") + "\n  got:  " + Std.string(got).split("\n").join("\\n"));
		}
	}
}
