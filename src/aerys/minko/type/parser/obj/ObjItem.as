package aerys.minko.type.parser.obj
{
	public class ObjItem
	{
		public static const GROUP 	: uint = 0;
		public static const OBJECT	: uint = 1;
		public static const FACE 	: uint = 2;
		public static const SURFACE	: uint = 3;
		public static const MTL 	: uint = 4;
		
		private static var _ids : uint 		= 0;
		
		private var _id 		: uint 		= _ids++;
		private var _name 		: String 	= ""
		private var _type 		: uint 		= 0;
		private var _surfaceId	: uint 		= 0;
		private var _xyzId		: Array 	= [];
		private var _uvId 		: Array 	= [];
		private var _normalId 	: Array 	= [];
		
		public function get type():uint
		{
			return _type;
		}

		public function set type(value:uint):void
		{
			_type = value;
		}

		public static function reset() : void
		{
			_ids = 0;
		}
		
		public function ObjItem(type : uint)
		{
			_type = type;
		}
		
		public function get id():uint
		{
			return _id;
		}

		public function get normalId():Array
		{
			return _normalId;
		}

		public function set normalId(value:Array):void
		{
			_normalId = value;
		}
		
		public function get uvId():Array
		{
			return _uvId;
		}

		public function set uvId(value:Array):void
		{
			_uvId = value;
		}

		public function get xyzId():Array
		{
			return _xyzId;
		}

		public function set xyzId(value:Array):void
		{
			_xyzId = value;
		}

		public function get surfaceId():uint
		{
			return _surfaceId;
		}

		public function set surfaceId(value:uint):void
		{
			_surfaceId = value;
		}

		public function get name():String
		{
			return _name;
		}

		public function set name(value:String):void
		{
			_name = value;
		}

	}
}