package game.living
{
	import road.game.resource.ActionMovie;

	/** Frame scripts as Flash CS writes them: frameN methods registered by
		addFrameScript, calling the base class (1), passing object literals (2,
		3) and keeping a local variable (4, opcodes the translator lacks). */
	public dynamic class Living extends ActionMovie
	{
		public function Living()
		{
			super();
			addFrameScript(0, this.frame1, 1, this.frame2, 2, this.frame3, 3, this.frame4);
		}

		internal function frame1():*
		{
			sendCommand("effect");
		}

		internal function frame2():*
		{
			sendCommand("focus", {"x": 0, "y": 0, "strategy": "shockingLinear", "speed": 20});
		}

		internal function frame3():*
		{
			sendCommand("focus", {"x": -200, "strategy": "default", "inner": {"a": 1}});
			stop();
		}

		internal function frame4():*
		{
			var next:int = totalFrames;
			gotoAndStop(next);
		}
	}
}
