package aerys.minko.type.parser.obj
{
    import aerys.minko.render.resource.texture.TextureResource;
    import aerys.minko.type.Signal;
    import aerys.minko.type.loader.ILoader;
    import aerys.minko.type.loader.parser.ParserOptions;
    
    import avmplus.getQualifiedClassName;
    
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    
    public final class MtlLoader implements ILoader
    {
        private var _progress			: Signal;
        private var _error				: Signal;
        private var _complete			: Signal;
        private var _isComplete			: Boolean;
        private var _document			: MtlDocument;
        private var _parserOptions		: ParserOptions;
        private var _loaderToMaterial	: Dictionary;
        private var _dependencyCounter  : uint;
        
		public function get document():MtlDocument
		{
			return _document;
		}

		public function set document(value:MtlDocument):void
		{
			_document = value;
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
        
        public function MtlLoader(parserOptions : ParserOptions)
        {
            _parserOptions = parserOptions;
            
            _isComplete 		= false;
            _error				= new Signal('MtlLoader.error');
            _progress			= new Signal('MtlLoader.progress');
            _complete			= new Signal('MtlLoader.complete');
            
            _document			= new MtlDocument();
            
            _loaderToMaterial	= new Dictionary();
            
            _dependencyCounter	= 0;
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
                
                throw new Error(
                    'No material data can be created from an object of type \'' + className + '\''
                );
            }
        }
        
        public function loadBytes(bytes : ByteArray) : void
        {
            bytes.position = 0;
            
            _document.fromMtlFile(bytes);
            
            for each (var material : ObjMaterialDefinition in _document.materials)
            {
                if (!material)
                {
                    continue;
                }
                
                for each (var mapRef : Object in [
                    {ref : material.diffuseMapRef, callback : diffuseMapCompleteHandler},
                    {ref : material.specularMapRef, callback : specularMapCompleteHandler},
                    {ref : material.normalMapRef, callback : normalMapCompleteHandler},
                    {ref : material.alphaMapRef, callback : alphaMapCompleteHandler}
                ])
                {
                    if (mapRef.ref && mapRef.callback)
                    {
                        var loader : ILoader = _parserOptions.dependencyLoaderFunction(mapRef.ref, mapRef.ref, true, _parserOptions);
                        if (loader)
                        {
                            _loaderToMaterial[loader] = material;
                            _dependencyCounter += 1;
                            loader.complete.add(mapRef.callback);
                            loader.error.add(mapErrorHandler);
                        }
                    }
                }
            }
            
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
        
        private function mapErrorHandler(loader			: ILoader,
                                         errorCode		: uint,
                                         errorText		: String) : void
        {
            _dependencyCounter -= 1;
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
        
        private function diffuseMapCompleteHandler(loader		: ILoader,
                                                   texture		: TextureResource) : void
        {
            var material : ObjMaterialDefinition = _loaderToMaterial[loader];
            
            if (material)
            {
                material.diffuseMap = texture;
				if (_parserOptions.assets)
					_parserOptions.assets.setTexture(material.diffuseMapRef, texture);
            }
            
            _dependencyCounter -= 1;
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
        
        private function specularMapCompleteHandler(loader		: ILoader,
                                                    texture		: TextureResource) : void
        {
            var material : ObjMaterialDefinition = _loaderToMaterial[loader];
            
            if (material)
			{
                material.specularMap = texture;
				if (_parserOptions.assets)
					_parserOptions.assets.setTexture(material.specularMapRef, texture);
			}
            
            _dependencyCounter -= 1;
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
        
        private function alphaMapCompleteHandler(loader		: ILoader,
                                                 texture	: TextureResource) : void
        {
            var material : ObjMaterialDefinition = _loaderToMaterial[loader];
            
            if (material)
			{
                material.alphaMap = texture;
				if (_parserOptions.assets)
					_parserOptions.assets.setTexture(material.alphaMapRef, texture);
			}
			
            _dependencyCounter -= 1;
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
        
        private function normalMapCompleteHandler(loader		: ILoader,
                                                  texture		: TextureResource) : void
        {
            var material : ObjMaterialDefinition = _loaderToMaterial[loader];
            
            if (material)
			{
                material.normalMap = texture;
				if (_parserOptions.assets)
					_parserOptions.assets.setTexture(material.normalMapRef, texture);
			}
			
            _dependencyCounter -= 1;
            if (_dependencyCounter == 0)
            {
                _isComplete = true;
                _complete.execute(this, _document);
            }
        }
    }
}