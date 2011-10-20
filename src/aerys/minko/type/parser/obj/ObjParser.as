package aerys.minko.type.parser.obj
{
	import aerys.minko.scene.node.IScene;
	import aerys.minko.type.parser.IParser;
	import aerys.minko.type.parser.ParserOptions;
	
	import flash.events.EventDispatcher;
	import flash.utils.ByteArray;
	
	public class ObjParser extends EventDispatcher implements IParser
	{
		private static const TEN_POWERS : Vector.<Number> = Vector.<Number>([
			1,
			0.1, 
			0.01, 
			0.001, 
			0.0001, 
			0.00001, 
			0.000001, 
			0.0000001, 
			0.00000001, 
			0.000000001, 
			0.0000000001,
			0.00000000001,
			0.000000000001,
			0.0000000000001
		]);
		
		private var _data					: Vector.<IScene>;
		
		private var _positions				: Vector.<Number>;
		private var _uvs					: Vector.<Number>;
		private var _normals				: Vector.<Number>;
		
		private var _groupNames				: Vector.<String>;
		private var _groupFacesPositions	: Vector.<Vector.<uint>>;
		private var _groupFacesUvs			: Vector.<Vector.<uint>>;
		private var _groupFacesNormals		: Vector.<Vector.<uint>>;
		
		public function ObjParser()
		{
			_data					= new Vector.<IScene>();
			
			_positions				= new Vector.<Number>();
			_uvs					= new Vector.<Number>();
			_normals				= new Vector.<Number>();
			
			_groupNames				= new Vector.<String>();
			_groupFacesPositions	= new Vector.<Vector.<uint>>();
			_groupFacesUvs			= new Vector.<Vector.<uint>>();
			_groupFacesNormals		= new Vector.<Vector.<uint>>();
		}
		
		public function get data() : Vector.<IScene>
		{
			return _data;
		}
		
		public function parse(data		: ByteArray, 
							  options	: ParserOptions) : Boolean
		{
			
			
			reset();
			readData(data);
			createMeshs();
			
			return true;
		}
		
		private function reset() : void
		{
			_data.length				= 0;
			
			_positions.length			= 0;
			_uvs.length					= 0;
			_normals.length				= 0;
			
			_groupNames.length			= 0;
			_groupFacesPositions.length	= 0;
			_groupFacesUvs.length		= 0;
			_groupFacesNormals.length	= 0;
		}
		
		private function readData(data : ByteArray) : void
		{
			data.position = 0;
			
			var currentMaterialId : uint = 0;
			while (data.position != data.length - 1)
			{
				var char : uint;
				switch (char = data.readUnsignedByte())
				{
					case 0x76: // "v"
						switch (data.readUnsignedByte())
						{
							case 0x20: // " "
								skipChars(data, 1);
								parseFloats(data, 3, _positions);
								break;
							
							case 0x6e: // "n"
								skipChars(data, 1);
								parseFloats(data, 3, _normals);
								
								break;
							
							case 0x74: // "t"
								skipChars(data, 1);
								parseFloats(data, 2, _uvs);
								break;
							
							default:
								throw new Error('Malformed OBJ file');
						}
						break;
					
					case 0x66: // "f"
						skipChars(data, 1);
						parseFace(data, currentMaterialId);
						break;
					
					case 0x67: // "g"
						gotoNextLine(data); // we ignore group instructions
						break;
					
					case 0x75: // "u"
						if (data.readUTFBytes(5) != 'semtl')
							throw new Error('Malformed OBJ file');
						
						skipChars(data, 1);
						currentMaterialId = retrieveMaterial(data);
						break;
					
					case 0x6d: // "m"
						if (data.readUTFBytes(5) != 'tllib')
							throw new Error('Malformed OBJ file');
						
						gotoNextLine(data); // we ignore mtllib instructions
						
						break;
					
					case 0x23: // "#"
					case 0x73: // "s"
						gotoNextLine(data); // we ignore smoothing group instructions
						break;
					
					case 0x0a: // "\n"
						break;
					
					default:
						throw new Error('Malformed OBJ file, found ' + char);
				}
			}
		}
		
		private function skipChars(data : ByteArray, numChars : uint = 1) : void
		{
			while (numChars--)
				data.readUnsignedByte();
		}
		
		private function gotoNextLine(data : ByteArray) : void
		{
			while (data.readUnsignedByte() != 0x0A)
				continue;
		}
		
		private function retrieveMaterial(data : ByteArray) : uint
		{
			var matName	: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
				matName += char;
			
			var materialId : int = _groupNames.indexOf(matName);
			if (materialId == -1)
			{
				materialId = _groupNames.length;
				
				_groupNames.push(matName)
				_groupFacesPositions.push(new Vector.<uint>());
				_groupFacesUvs.push(new Vector.<uint>());
				_groupFacesNormals.push(new Vector.<uint>());
			}
			
			return materialId;
		}
		
		private function parseFloats(data : ByteArray, nbFloats : uint, destination : Vector.<Number>) : void
		{
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
					else
					{
						break;
					}
				}
				
				destination.push(isPositive * currentDigits * TEN_POWERS[decimalOpPower]);
			}
			
			gotoNextLine(data);
		}
		
		/**
		 * @param data
		 * @param buffers contains the position buffer on the first index, the uvs on the second one, and the normals on the third
		 */
		private function parseFace(data			: ByteArray, 
								   materialId	: uint) : void
		{
			var currentIndex			: uint = 0;
			
			// 0: position, 1: uv, 2: normal
			var currentIndexSemantic	: uint						= 0;
			var buffers					: Vector.<Vector.<uint>>	= Vector.<Vector.<uint>>([
				_groupFacesPositions[materialId],
				_groupFacesUvs[materialId],
				_groupFacesNormals[materialId]
			]);
			
			while (true)
			{
				var readChar		: uint = data.readUnsignedByte();
				if (readChar >= 0x30 && readChar < 0x3a)
				{
					currentIndex = 10 * currentIndex + readChar - 0x30;
				}
				else if (readChar == 0x2f) // "/"
				{
					++currentIndexSemantic;
				}
				else if (readChar == 0x20) // " "
				{
					buffers[currentIndexSemantic].push(currentIndex);
					currentIndex = 0;
					currentIndexSemantic = 0;
				}
				else if (readChar == 0x0a) // "\n"
				{
					break;
				}
				else
				{
					throw new Error('Malformed OBJ file');
				}
			}
		}
		
		private function createMeshs() : void
		{
			trace('finished');
		}
		
		
	}
}