package aerys.minko.type.parser.obj
{
	import aerys.minko.Minko;
	import aerys.minko.type.error.obj.ObjError;
	import aerys.minko.type.loader.parser.ParserOptions;
	import aerys.minko.type.log.DebugLevel;
	
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.getTimer;

	public final class MtlDocument
	{
		private static const TEN_POWERS					: Vector.<Number> = Vector.<Number>([
			1, 0.1, 0.01, 0.001, 0.0001, 0.00001, 0.000001,
			0.0000001, 0.00000001, 0.000000001, 0.0000000001,
			0.00000000001, 0.000000000001, 0.0000000000001
		]);
		
		private static const FLOAT_CONTAINER			: Vector.<Number> = Vector.<Number>([0, 0, 0]);
		
		private var _currentLine						: uint;
		private var _isLoaded							: Boolean;
		
		private var _materials							: Object;
		private var _currentMaterialName				: String;
		private var _currentMaterial					: ObjMaterial;
		
		public function MtlDocument()
		{
			_currentLine	= 0;
			_isLoaded		= false;
			_materials		= new Object();
		}
		
		public function get isLoaded() : Boolean
		{
			return _isLoaded;
		}
		
		public function get materials() : Object
		{
			return _materials
		}
		
		public function fromMtlFile(data : ByteArray) : Boolean
		{
			try
			{
				if (!_isLoaded)
				{
					var t : uint = getTimer();
					readData(data);
					Minko.log(DebugLevel.PLUGIN_NOTICE, 'mtl: material template library parsing:' + (getTimer() - t).toString());
					_isLoaded = true;
				}
				
				return true;
			}
			catch (e : ObjError)
			{
				Minko.log(DebugLevel.PLUGIN_ERROR, e.message);
			}
			catch (e : Error)
			{
				Minko.log(DebugLevel.LOAD_ERROR, e.message);
			}
			
			return false;
		}
		
		private function readData(data : ByteArray) : void
		{
			data.position = 0;
			
			var currentMaterialId : uint = 0;
			while (data.position != data.length)
			{
				var char		: uint;
				var secondChar	: uint
				switch (char = data.readUnsignedByte())
				{
					case 0x6e: // n
					{
						if (data.readUTFBytes(5) == 'ewmtl')
						{
							eatSpaces(data);
							parseNewMtl(data);
						}
						else
						{
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "newmtl"?');
						}
						
						break;
					}
						
					case 0x4b: // K
					{
						secondChar = data.readUnsignedByte();
						switch (secondChar)
						{
							case 0x61: //'a'
								eatSpaces(data);
								parseAmbient(data);
								break;
							case 0x64: //'d'
								eatSpaces(data);
								parseDiffuse(data);
								break;
							case 0x73: //'s'
								eatSpaces(data);
								parseSpecular(data);
								break;
							case 0x65:
								gotoNextLine(data);
								break;
							default:
								throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean Ka, Kd or Ks?');
						}
						
						break;
					}
						
					case 0x64: //'d'
						eatSpaces(data);
						parseAlpha(data);
						break;
					case 0x54: //'T'
					{
						gotoNextLine(data);
						break;		
					}
						
					case 0x4e: //'N'
					{
						secondChar = data.readUnsignedByte();
						if (secondChar == 0x73) //'s'
						{
							eatSpaces(data);
							parseShininess(data);
						}
						else
						{
							gotoNextLine(data);
						}
						
						break;
					}
						
					case 0x69: //'i'
					{
						if (data.readUTFBytes(4) == 'llum')
						{
							eatSpaces(data);
							parseIllumination(data);
						}
						else
						{
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "illum"?');
						}
						
						break;
					}
						
					case 0x6d: //'m'
					{
						if (data.readUTFBytes(4) == 'ap_K')
						{
							secondChar = data.readUnsignedByte();
							if (secondChar == 0x64) //'d'
							{
								eatSpaces(data);
								parseDiffuseMap(data);
							}
							else
							{
								gotoNextLine(data);
							}
						}
						else
						{
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "map_"?');
						}
						
						break;
					}
						
					case 35: // "#"
					case 0x73: // "s"
					case 0x0d: // "\r"
						gotoNextLine(data); // we ignore smoothing group instructions
						break;
					
					case 0x0a: // "\n"
					case 0x09: // tab
					case 0x20: // space
						break;
					
					default:
						throw new ObjError('Line ' + _currentLine + ': unknown definition, found ' + char);
				}
			}
		}
				
		private function skipChars(data : ByteArray, numChars : uint = 1) : void
		{
			while (numChars--)
				data.readUnsignedByte();
		}
		
		private function eatSpaces(data : ByteArray) : void
		{
			while (data.readUnsignedByte() == 0x20)
				continue;
			--data.position;
		}
		
		private function gotoNextLine(data : ByteArray) : void
		{
			while (data.readUnsignedByte() != 0x0a)
				continue;
			++_currentLine;
		}

		private function parseFloats(data : ByteArray, nbFloats : uint, destination : Vector.<Number>) : void
		{
			var eolReached : Boolean = false;
			
			for (var i : uint = 0; i < nbFloats; ++i)
			{
				var currentDigits	: uint		= 0;
				var isPositive		: Number	= 1;
				var isDecimalPart	: uint		= 0;
				var decimalOpPower	: uint		= 0;
				
				while (true)
				{
					var readChar : uint = data.readUnsignedByte();
					
					if (readChar == 0x2d) // "-"
					{
						isPositive *= -1;
						
					}
					else if (readChar >= 0x30 && readChar < 0x3a)
					{
						currentDigits = 10 * currentDigits + readChar - 0x30;
						decimalOpPower += isDecimalPart;
					}
					else if (readChar == 0x2e) // "."
					{
						isDecimalPart = 1;
					}
					else if (readChar == 0x20)
					{
						break;
					}
					else if (readChar == 0x0d)
					{
						break;
					}
					else if (readChar == 0x0a)
					{
						++_currentLine;
						eolReached = true;
						break;
					}
					else
					{
						throw new ObjError('Line ' + _currentLine + ': invalid float');
					}
				}
				
				destination.push(isPositive * currentDigits * TEN_POWERS[decimalOpPower]);
			}
			
			if (!eolReached)
				gotoNextLine(data);
		}
		
		private function parseNewMtl(data : ByteArray) : void
		{
			var matName	: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					matName += char;
			}
			
			if ((_currentMaterial = _materials[matName]))
			{
				throw new ObjError('Line ' + _currentLine + ': material redefinition');
			}
			
			_currentMaterial = new ObjMaterial();
			_materials[matName] = _currentMaterial;
			
			gotoNextLine(data);
		}
		
		private function parseAmbient(data : ByteArray) : void
		{
			parseFloats(data, 3, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.ambientR = FLOAT_CONTAINER[0];
			_currentMaterial.ambientG = FLOAT_CONTAINER[1];
			_currentMaterial.ambientB = FLOAT_CONTAINER[2];
		}
		
		private function parseDiffuse(data : ByteArray) : void
		{
			parseFloats(data, 3, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.diffuseR = FLOAT_CONTAINER[0];
			_currentMaterial.diffuseG = FLOAT_CONTAINER[1];
			_currentMaterial.diffuseB = FLOAT_CONTAINER[2];
			
			gotoNextLine(data);
		}
		
		private function parseSpecular(data : ByteArray) : void
		{
			parseFloats(data, 3, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.specularR = FLOAT_CONTAINER[0];
			_currentMaterial.specularG = FLOAT_CONTAINER[1];
			_currentMaterial.specularB = FLOAT_CONTAINER[2];
		}
		
		private function parseAlpha(data : ByteArray) : void
		{
			parseFloats(data, 1, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.alpha = FLOAT_CONTAINER[0];
			
			gotoNextLine(data);
		}
		
		private function parseShininess(data : ByteArray) : void
		{
			parseFloats(data, 1, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.shininess = FLOAT_CONTAINER[0];
			
			gotoNextLine(data);
		}
		
		private function parseIllumination(data : ByteArray) : void
		{
			parseFloats(data, 1, FLOAT_CONTAINER);
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}
			
			_currentMaterial.illumination = FLOAT_CONTAINER[0];
			
			gotoNextLine(data);
		}
		
		private function parseDiffuseMap(data : ByteArray) : void
		{
			var mapName	: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					mapName += char;
			}
			
			if (_currentMaterial == null)
			{
				throw new ObjError('Line ' + _currentLine + ': no material found');
			}

			_currentMaterial.diffuseMapRef = mapName;
			
			gotoNextLine(data);
		}
	}
}