package aerys.minko.type.parser.obj
{
	import aerys.minko.type.Signal;
	import aerys.minko.type.loader.ILoader;
	import aerys.minko.type.loader.parser.IParser;
	import aerys.minko.type.loader.parser.ParserOptions;
	
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	
	public final class ObjParser implements IParser
	{
		private var _document			: ObjDocument;
		private var _mtlDocument		: MtlDocument;
		private var _options			: ParserOptions;
		private var _error				: Signal;
		private var _progress			: Signal;
		private var _complete			: Signal;
		private var _loaderToDependency	: Dictionary;
		private var _lastData			: ByteArray;

		public function ObjParser(options : ParserOptions)
		{
			_options			= options || new ParserOptions();
			_progress			= new Signal('ObjParser.progress');
			_complete			= new Signal('ObjParser.complete');
			_error				= new Signal('ObjParser.error');
			_loaderToDependency	= new Dictionary();
			_document			= new ObjDocument();
		}
		
		public function get error():Signal
		{
			return _error;
		}
		
		public function get progress():Signal
		{
			return _progress;
		}
		
		public function get complete():Signal
		{
			return _complete;
		}
		
		public function isParsable(data:ByteArray):Boolean
		{
			var isObj	: Boolean = false;
			
			try
			{
				if (!(isObj = data.length > 0))
				{
					return false;
				}
				
				_lastData			= data;
				_lastData.position	= 0;
			}
			catch (e : Error)
			{
				isObj = false;
			}
			
			if (!isObj)
			{
				_lastData = null;
			}
			
			return isObj;
		}
		
		public function getDependencies(data : ByteArray) : Vector.<ILoader>
		{
			if (_lastData !== data)
			{
				XML.prettyPrinting = false;
				
				_lastData			= data;
				_lastData.position	= 0;
			}
			
			_document.fromObjFile(data, _options);
			var dependencies : Vector.<ILoader> = new <ILoader>[];
			for each (var mtl : String in _document.MtlFiles)
			{
				var loader	: ILoader	= _options.dependencyLoaderFunction(mtl, mtl, false, _options);
                
				if (loader)
				{
					if (loader is MtlLoader)
					{
						var mtlLoader	: MtlLoader	= MtlLoader(loader);
						if (mtlLoader.isComplete)
						{
							mtlCompleteHandler(loader, mtlLoader.document);
						}
						else
						{
							loader.complete.add(mtlCompleteHandler);
							dependencies.push(loader);
						}
					}
				}
			}
			
			return dependencies;
		}
		
		private function mtlCompleteHandler(loader	: ILoader,
                                            doc		: MtlDocument) : void
		{
			_mtlDocument = doc;
		}
		
		public function parse():void
		{
			_complete.execute(this, _document.createScene(_mtlDocument));
		}
	}
}