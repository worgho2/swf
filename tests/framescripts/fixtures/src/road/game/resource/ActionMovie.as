package road.game.resource
{
	import flash.display.MovieClip;
	import flash.events.Event;

	/** The base class of the animated characters of DDTank (ActionMovie of the
		game's asset SWFs): its frame scripts call the protected sendCommand. */
	public class ActionMovie extends MovieClip
	{
		public var commands:Array = [];

		public function ActionMovie()
		{
			super();
		}

		protected function sendCommand(type:String, data:Object = null):void
		{
			commands.push([type, data]);
			dispatchEvent(new Event(type));
		}
	}
}
