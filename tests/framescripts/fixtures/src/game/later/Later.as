package game.later
{
	import flash.display.MovieClip;

	/** A class of the second frame: mxmlc writes it in a DoABC of its own,
		after the one of the first frame (like core.swf, choicefigure.swf and
		loading.swf of DDTank, three DoABC each). */
	public dynamic class Later extends MovieClip
	{
		public function Later()
		{
			super();
			addFrameScript(0, this.frame1);
		}

		internal function frame1():*
		{
			gotoAndPlay("later");
		}
	}
}
