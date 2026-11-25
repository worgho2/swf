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

		// 1. A method of the base class defined in the SWF itself: Flash CS and
		// mxmlc name the protected sendCommand of ActionMovie by a QName in its
		// protected namespace, "road.game.resource:ActionMovie".
		var scripts = FrameScriptParser.convertToJS(living, "game.living.Living");
		equals("base class method", '\nthis.sendCommand("effect");', scripts[0]);

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
