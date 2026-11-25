package
{
	import flash.display.Sprite;
	import game.living.Living;

	/** The document class: it only references what the fixture keeps. */
	public class Main extends Sprite
	{
		public function Main()
		{
			super();
			addChild(new Living());
		}
	}
}
