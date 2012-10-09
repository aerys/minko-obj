package aerys.minko.type.parser.obj
{
	import aerys.minko.render.resource.texture.TextureResource;
	import aerys.minko.type.Signal;
	import aerys.minko.type.loader.ILoader;
	import aerys.minko.type.loader.parser.ParserOptions;
	
	import avmplus.getQualifiedClassName;
	
	import flash.display.Loader;
	import flash.display3D.textures.Texture;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	
	public final class MtlLoader implements ILoader
	{
		private var _progress					: Signal;
		private var _error						: Signal;
		private var _complete					: Signal;
		private var _isComplete					: Boolean;
		private var _document					: MtlDocument;
		private var _parserOptions				: ParserOptions;
		private var _loaderToMaterial			: Object;
		private var _dependencyCounter			: uint;
		
		public function MtlLoader(parserOptions : ParserOptions)
		{
			_parserOptions = parserOptions;
			
			_isComplete 		= false;
			_error				= new Signal('TextureLoader.error');
			_progress			= new Signal('TextureLoader.progress');
			_complete			= new Signal('TextureLoader.complete');
			
			_document			= new MtlDocument();
			
			_loaderToMaterial	= new Object();
			
			_dependencyCounter	= 0;
		}
		
		public function get progress() : Signal
		{
			return _progress;
		}
		
		public function get error() : Signal
		{
			return _error;
		}
		
		public function get complete() : Signal
		{
			return _complete;
		}
		
		public function get isComplete() : Boolean
		{
			return _isComplete;
		}
		
		public function load(urlRequest:URLRequest):void
		{
			var loader : URLLoader = new URLLoader();
			
			loader.dataFormat = URLLoaderDataFormat.BINARY;
			loader.addEventListener(ProgressEvent.PROGRESS, loadProgressHandler);
			loader.addEventListener(Event.COMPLETE, loadCompleteHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, loadIoErrorHandler);
			loader.load(urlRequest);
		}
		
		private function loadIoErrorHandler(e : IOErrorEvent) : void
		{
			_error.execute(this, e.errorID, e.text);
		}
		
		private function loadProgressHandler(e : ProgressEvent) : void
		{
			_progress.execute(this, e.bytesLoaded, e.bytesTotal);
		}
		
		private function loadCompleteHandler(e : Event) : void
		{
			loadBytes(URLLoader(e.currentTarget).data);
		}

		public function loadClass(classObject : Class) : void
		{
			var assetObject : Object		= new classObject();
			
			if (assetObject is ByteArray)
			{
				loadBytes(ByteArray(assetObject));
			}
			else
			{
				var className : String = getQualifiedClassName(classObject);
				className = className.substr(className.lastIndexOf(':') + 1);
				
				_isComplete = true;
				
				throw new Error('No material data can be created from an object of type \'' + className + '\'');
			}
		}
		
		public function loadBytes(bytes : ByteArray) : void
		{
			bytes.position = 0;
			
			_document.fromMtlFile(bytes);
			
			for each (var material : ObjMaterial in _document.materials)
			{
				if (!material)
				{
					continue;
				}
				
				if (material.diffuseMapRef)
				{
					var loader : ILoader = _parserOptions.dependencyLoaderFunction(material.diffuseMapRef, true, _parserOptions);
					_loaderToMaterial[loader] = material;
					_dependencyCounter += 1;
					loader.complete.add(diffuseMapCompleteHandler);
				}
			}
			
			if (_dependencyCounter == 0)
			{
				_complete.execute(this, _document);
			}
		}
		
		private function diffuseMapCompleteHandler(loader		: ILoader,
												   texture		: TextureResource) : void
		{
			var material : ObjMaterial = _loaderToMaterial[loader];
			
			if (material)
			{
				material.diffuseMap = texture;
			}
			
			_dependencyCounter -= 1;
			if (_dependencyCounter == 0)
			{
				_complete.execute(this, _document);
			}
		}
	}
}