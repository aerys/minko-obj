package aerys.minko.type.parser.obj
{
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.getTimer;
	
	import aerys.minko.Minko;
	import aerys.minko.render.geometry.Geometry;
	import aerys.minko.render.geometry.GeometrySanitizer;
	import aerys.minko.render.geometry.stream.IVertexStream;
	import aerys.minko.render.geometry.stream.IndexStream;
	import aerys.minko.render.geometry.stream.StreamUsage;
	import aerys.minko.render.geometry.stream.VertexStream;
	import aerys.minko.render.geometry.stream.format.VertexFormat;
	import aerys.minko.render.material.Material;
	import aerys.minko.render.material.basic.BasicProperties;
	import aerys.minko.render.material.phong.PhongProperties;
	import aerys.minko.render.shader.compiler.CRC32;
	import aerys.minko.scene.node.Group;
	import aerys.minko.scene.node.ISceneNode;
	import aerys.minko.scene.node.Mesh;
	import aerys.minko.type.enum.Blending;
	import aerys.minko.type.enum.NormalMappingType;
	import aerys.minko.type.error.obj.ObjError;
	import aerys.minko.type.loader.AssetsLibrary;
	import aerys.minko.type.loader.parser.ParserOptions;
	import aerys.minko.type.log.DebugLevel;
	
	public final class ObjDocument
	{
		private static const TEN_POWERS					: Vector.<Number> = Vector.<Number>([
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
		
		private var _options				: ParserOptions			= null;
		private var _currentLine			: uint					= 0;
		private var _positions				: Vector.<Number>		= new Vector.<Number>();
		private var _uvs					: Vector.<Number>		= new Vector.<Number>();
		private var _normals				: Vector.<Number>		= new Vector.<Number>();
		private var _queue 					: Vector.<ObjItem> 		= new Vector.<ObjItem>();
		private var _isLoaded				: Boolean				= false;
		private var _mtlFiles				: Vector.<String>		= new Vector.<String>();
		
		public function get MtlFiles() : Vector.<String>
		{
			return _mtlFiles;
		}
		
		public function fromObjFile(data		: ByteArray, 
									options		: ParserOptions) : Boolean
		{
			try
			{
				if (!_isLoaded)
				{
					_options = options;
					reset();
					
					var t : uint = getTimer();
					readData(data);
					Minko.log(DebugLevel.PLUGIN_NOTICE, 'obj: vertices and indexes parsing:' + (getTimer() - t).toString());
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
		
		private function reset() : void
		{
			_currentLine				= 1;
			_positions.length			= 0;
			_uvs.length					= 0;
			_normals.length				= 0;
			_isLoaded 					= false;
		}
		
		private function readData(data : ByteArray) : void
		{
			var dataLenght 	: uint = data.length;
			var char 		: uint = 0;
			
			data.position = 0;
			
			while (data.position != dataLenght)
			{
				char = data.readUnsignedByte();
				
				switch (char)
				{
					case 0x76: // "v"
						parseVertex(data);
						break;
					
					case 0x66: // "f"
						skipChars(data, 1);
						parseFace(data);
						break;
					
					case 0x67: // "g"
						eatSpaces(data);
						pushGroupName(data);
						break;
					
					case 0x75: // "u"
						if (data.readUTFBytes(5) != 'semtl')
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "usemtl"?');
						skipChars(data, 1);
						retrieveMaterial(data);
						break;
					
					case 0x6d: // "m"
						var str : String = data.readUTFBytes(5);
						if (str != 'tllib')
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "mtllib"?');
						eatSpaces(data);
						parseMtllib(data);
						break;
					
					case 0x0a: // "\n"
						++_currentLine;
						break;
					
					case 0x6f: // "o"
						parseObjectName(data);
						break;
					
					case 0x73: // "s"
						eatSpaces(data);
						parseSurface(data);
						break
					case 0x23: // "#"
					case 0x0d: // "\r"
					default:
						gotoNextLine(data); // we ignore smoothing group instructions
						break;
				}
			}
		}
		
		private function parseVertex(data : ByteArray) : void
		{
			switch (data.readUnsignedByte())
			{
				case 0x20: // " " xyz
					eatSpaces(data);
					parseFloats(data, 3, _positions);
					break;
				
				case 0x6e: // "n" normal
					eatSpaces(data);
					parseFloats(data, 3, _normals);
					
					break;
				
				case 0x74: // "t" uv
					eatSpaces(data);
					parseFloats(data, 2, _uvs);
					break;
				
				default:
					throw new ObjError('Line ' + _currentLine + ': unknown vertex declaration');
			}
		}
		
		private function parseSurface(data : ByteArray) : void
		{
			var char		: String	= "";
			var surfaceName : String 	= ""
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					surfaceName += char;
			}
			
			var surfaceId : int = parseInt(surfaceName);
			
			if (!isNaN(surfaceId))
			{
				var objItem : ObjItem = new ObjItem(ObjItem.SURFACE);
							
				objItem.surfaceId = surfaceId;
							
				_queue.push(objItem);
			}
		}
		
		private function parseObjectName(data:ByteArray):void
		{
			var char		: String	= "";
			var objectName 	: String 	= ""
			
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					objectName += char;
			}
			
			var objItem : ObjItem = new ObjItem(ObjItem.OBJECT);
			
			objItem.name = objectName;
			_queue.push(objItem);
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
		
		private function pushGroupName(data : ByteArray) : void
		{
			var groupName 	: String = "";
			var char 		: String = "";
			
			while ((char = data.readUTFBytes(1)) != '\n')
				if (char != '\r')
					groupName += char;
			
			var objItem : ObjItem = new ObjItem(ObjItem.GROUP);
			
			if (groupName == "")
				groupName = "Group_" + objItem.id;
			
			objItem.name = groupName;
			
			_queue.push(objItem);
		}
		
		private function retrieveMaterial(data : ByteArray) : void
		{
			var matName	: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					matName += char;
			}
			
			++_currentLine;
			
			var objItem : ObjItem = new ObjItem(ObjItem.MTL);
			objItem.name = matName;
			_queue.push(objItem);
		}
		
		private function parseMtllib(data : ByteArray) : void
		{
			var mtl		: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
				if (char != '\r')
					mtl += char;
			
			_mtlFiles.push(mtl);
		}
		
		private function getFloat(data : ByteArray, lastReadChar : Array = null) : Number
		{
			var currentDigits	: uint		= 0;
			var isPositive		: Number	= 1;
			var isDecimalPart	: uint		= 0;
			var decimalOpPower	: uint		= 0;
			var readChar		: uint		= data.readUnsignedByte();
			
			if (readChar == 0x2d) // "-"
			{
				isPositive = -1;
				readChar = data.readUnsignedByte();
			}
			
			while (readChar != 0x0a
				&& (readChar != 0x20)
				&& (readChar != 0x09)
				&& (readChar != 0x65)
				&& (readChar != 0x45))
			{
				if (readChar >= 0x30 && readChar < 0x3a)
				{
					currentDigits = 10 * currentDigits + readChar - 0x30;
					decimalOpPower += isDecimalPart;
				}
				else if (readChar == 0x2e) // "."
				{
					isDecimalPart = 1;
				}
				
				readChar = data.readUnsignedByte();
			}
			
			if (lastReadChar != null)
				lastReadChar[0] = readChar;
			
			if (decimalOpPower > TEN_POWERS.length - 1)
				decimalOpPower = TEN_POWERS.length - 1;
			
			return isPositive * currentDigits * TEN_POWERS[decimalOpPower];
		}
		
		private function parseFloats(data : ByteArray, nbFloats : uint, destination : Vector.<Number>) : void
		{
			var lastReadChar		: Array		= new Array();
			
			for (var i : uint = 0; i < nbFloats; ++i)
			{
				var floatValue		: Number	= getFloat(data, lastReadChar);
				if ((lastReadChar[0] == 0x65) || (lastReadChar[0] == 0x45))
				{
					var powerOfTen 	: Number	= getFloat(data, lastReadChar);
					floatValue = floatValue * Math.pow(10, powerOfTen);
				}
				
				destination.push(floatValue);
			}
			
			if (lastReadChar[0] == 0x0a)
				++_currentLine;
			else
				gotoNextLine(data);
		}
		
		private function parseFace(data			: ByteArray) : void
		{
			var char 		: String = "";
			var faceString 	: String = "";
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					faceString += char;
			}
			
			var faceArray 	: Array = faceString.split(" ");
			var t1 			: Array = faceArray[0].split("/");
			var t2  		: Array = faceArray[1].split("/");
			var t3			: Array = faceArray[2].split("/");
			
			var objItem : ObjItem = new ObjItem(ObjItem.FACE);
			
			objItem.xyzId 		= [parseInt(t1[0]),	parseInt(t2[0]), parseInt(t3[0])];
			objItem.uvId 		= [parseInt(t1[1]), parseInt(t2[1]), parseInt(t3[1])];
			objItem.normalId 	= [parseInt(t1[2]), parseInt(t2[2]), parseInt(t3[2])];
			objItem.name		= faceString;
			
			_queue.push(objItem);
		}
		
		public function createScene(mtlDoc : MtlDocument)	: Group
		{
			if (!_isLoaded)
				return null;
			
			var assets 						: AssetsLibrary 	= new AssetsLibrary();
			var result 						: Group 			= new Group();
			var currentIndexStream			: Vector.<uint> 	= new Vector.<uint>();
			var currentVertexStream 		: Vector.<Number>	= new Vector.<Number>();
			var currentObjectName 			: String 			= null;
			var numObjItem 					: uint 				= _queue.length;
			var currentGroup 				: Group 			= null;
			var currentMaterial 			: Material 			= null;
			var signatureToIndex			: Dictionary		= new Dictionary();
			var currentIndex 				: uint 				= 0;
			var maxIndice 					: uint 				= _positions.length / 3;
			var vertexFormat 				: VertexFormat		= (_normals.length > 0) ? VertexFormat.XYZ_UV_NORMAL : VertexFormat.XYZ_UV;
			
			if (_options.assets != null)
				assets = _options.assets;
			else
				_options.assets = assets;
			
			for (var i : uint = 0; i < numObjItem; ++i)
			{
				var objItem : ObjItem = _queue[i];
				
				switch(objItem.type)
				{
					case ObjItem.GROUP:
						var groups 	: Vector.<ISceneNode> = result.get("//Group[name='"+ objItem.name + "']");
						
						if (groups.length == 0)
						{
							currentGroup = new Group();
							currentGroup.name = objItem.name;
							result.addChild(currentGroup);
						}
						else
							currentGroup = groups[0] as Group;
						
						break;
					
					case ObjItem.MTL :
						var materialName : String = objItem.name;
						
						currentMaterial = assets.getMaterialByName(materialName);
						
						if (currentMaterial == null)
						{
							currentMaterial = createOrGetMaterial(mtlDoc.materials[materialName], materialName);
							assets.setMaterial(materialName, currentMaterial);
						}
						
						break;
					
					case ObjItem.OBJECT :
						currentObjectName = objItem.name;
						break;
					
					case ObjItem.FACE:
						var name 		: String		= objItem.name;
						var xyz 		: Array 		= objItem.xyzId;
						var normal 		: Array 		= objItem.normalId;
						var uv 			: Array 		= objItem.uvId;
						var vertice0Id	: Vector.<uint> = new Vector.<uint>(); vertice0Id.push(xyz[0], uv[0], normal[0]); 
						var vertice1Id	: Vector.<uint> = new Vector.<uint>(); vertice1Id.push(xyz[1], uv[1], normal[1]);
						var vertice2Id 	: Vector.<uint> = new Vector.<uint>(); vertice2Id.push(xyz[2], uv[2], normal[2]);
						var signature0 	: uint 			= CRC32.computeForUintVector(vertice0Id);
						var signature1	: uint 			= CRC32.computeForUintVector(vertice1Id);
						var signature2 	: uint 			= CRC32.computeForUintVector(vertice2Id);
						
						var index0 	: uint = 0;
						var index1 	: uint = 0;
						var index2 	: uint = 0;
							
						if (signatureToIndex[signature0] != null)
							index0 = signatureToIndex[signature0];
						else
						{
							var xyzIndex 	: uint = vertice0Id[0] - 1;
							var uvIndex 	: uint = vertice0Id[1] - 1;
							var nIndex 		: uint = vertice0Id[2] - 1;
							
							if (_normals.length > 0)
							{
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], _uvs[uint(uvIndex * 2 + 1)],
									_normals[uint(nIndex * 3)], _normals[uint(nIndex * 3 + 1)], _normals[uint(nIndex * 3 + 2)]);
							}
							else
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], _uvs[uint(uvIndex * 2 + 1)]);
							
							index0 = currentIndex++;
							signatureToIndex[signature0] = index0;
						}
						
						if (signatureToIndex[signature1] != null)
							index1 = signatureToIndex[signature1];
						else
						{
							var xyzIndex 	: uint = vertice1Id[0] - 1;
							var uvIndex 	: uint = vertice1Id[1] - 1;
							var nIndex 		: uint = vertice1Id[2] - 1;
							
							if (_normals.length > 0)
								
							{
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], 		_uvs[uint(uvIndex * 2 + 1)],
									_normals[uint(nIndex * 3)], 	_normals[uint(nIndex * 3 + 1)], _normals[uint(nIndex * 3 + 2)]);
							}
							else
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], 		_uvs[uint(uvIndex * 2 + 1)]);
							
							index1 = currentIndex++;
							signatureToIndex[signature1] = index1;
						}
						
						if (signatureToIndex[signature2] != null)
							index2 = signatureToIndex[signature2];
						else
						{
							var xyzIndex 	: uint = vertice2Id[0] - 1;
							var uvIndex 	: uint = vertice2Id[1] - 1;
							var nIndex 		: uint = vertice2Id[2] - 1;
							
							if (_normals.length > 0)
							{
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], _uvs[uint(uvIndex * 2 + 1)],
									_normals[uint(nIndex * 3)], _normals[uint(nIndex * 3 + 1)], _normals[uint(nIndex * 3 + 2)]);
							}
							else
								currentVertexStream.push(
									_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)],
									_uvs[uint(uvIndex * 2)], _uvs[uint(uvIndex * 2 + 1)]);
							
							index2 = currentIndex++;
							signatureToIndex[signature2] = index2;
						}
						
						currentIndexStream.push(index0, index2, index1);
						
						
						if (i == numObjItem - 1 || (_queue[i + 1].type != ObjItem.FACE && _queue[i + 1].type != ObjItem.SURFACE))
						{
							if (currentGroup == null)
								currentGroup = result;
							
							var meshes : Vector.<Mesh> = buildMeshes(currentIndexStream, currentVertexStream, vertexFormat, currentMaterial, currentObjectName);
							
							for each (var mesh : Mesh in meshes)
							{
								currentGroup.addChild(mesh);
								assets.setGeometry(mesh.name + "_geometry", mesh.geometry);
							}
							
							currentObjectName = null;
							currentVertexStream.length = 0;
							currentIndex = 0;
							signatureToIndex = new Dictionary();
							currentIndexStream.length = 0;
						}
						
						break;
					
					case ObjItem.SURFACE:
						break;
				}
			}
			
			return result;
		}
		
		private function buildMeshes(indexStreamData 	: Vector.<uint>,
									 vertexStreamData	: Vector.<Number>,
									 vertexFormat		: VertexFormat,
									 material 			: Material,
									 objectName 		: String) : Vector.<Mesh>
		{
			var meshes : Vector.<Mesh> = new Vector.<Mesh>();
			
			var vertexStream : VertexStream = VertexStream.fromVector(StreamUsage.DYNAMIC, vertexFormat, vertexStreamData);
			
			var vertexStreams 	: Vector.<ByteArray> = new Vector.<ByteArray>();
			var indexStreams 	: Vector.<ByteArray> = new Vector.<ByteArray>();
			
			var vertexByteArray 	: ByteArray = vertexStream.lock();
			
			GeometrySanitizer.splitBuffers(vertexByteArray, indexStreamData, vertexStreams, indexStreams, vertexFormat.numBytesPerVertex);
			
			vertexStream.unlock(false);
			vertexStream.dispose();
			
			for (var i : uint = 0; i < indexStreams.length; ++i)
			{
				vertexStreams[i].position = 0;
				indexStreams[i].position = 0;
				GeometrySanitizer.removeDuplicatedVertices(vertexStreams[i], indexStreams[i], vertexFormat.numBytesPerVertex);
				GeometrySanitizer.removeUnusedVertices(vertexStreams[i], indexStreams[i], vertexFormat.numBytesPerVertex);
				var vertexStream 	: VertexStream 	= new VertexStream(_options.vertexStreamUsage, vertexFormat, vertexStreams[i]);
				var indexStream 	: IndexStream 	= new IndexStream(_options.indexStreamUsage, indexStreams[i]);
				var geometry 		: Geometry 		= new Geometry(new <IVertexStream>[vertexStream], indexStream);
				var name 			: String 		= objectName;
				
				
				if (i > 0 && objectName != null && objectName != "")
					name = objectName + "_" + i;
				
				var mesh 			: Mesh 			= new Mesh(geometry, material, name);
				
				meshes.push(mesh);
			}
			
			return meshes;
		}
		
		private function toRGBA(r : Number, g : Number, b : Number, a : Number) : uint
		{
			var color : uint = 0;
			color = (color) + (r * 255);
			color = (color << 8) + (g * 255);
			color = (color << 8) + (b * 255);
			color = (color << 8) + (a * 255);
			
			return color;
		}
		
		private function createOrGetMaterial(matDef : ObjMaterialDefinition, materialName : String) : Material
		{
			var material	: Material;
			var color 		: uint;
			
			material = Material(_options.material.clone());
			material.name = materialName;
			
			if (matDef)
			{
				if (matDef.diffuseExists)
					material.setProperty(BasicProperties.DIFFUSE_COLOR, toRGBA(matDef.diffuseR, matDef.diffuseG, matDef.diffuseB, matDef.alpha));
				
				if (matDef.specularExists)
					material.setProperty(PhongProperties.SPECULAR, (matDef.specularR, matDef.specularG, matDef.specularB, 1));
				
				if (matDef.diffuseMapRef && matDef.diffuseMap)
					material.setProperty(BasicProperties.DIFFUSE_MAP, matDef.diffuseMap);
				
				if (matDef.specularMapRef && matDef.specularMap)
					material.setProperty(PhongProperties.SPECULAR_MAP, matDef.specularMap);
				
				if (matDef.normalMapRef && matDef.normalMap)
				{
					material.setProperty(PhongProperties.NORMAL_MAP, matDef.normalMap);
					material.setProperty(PhongProperties.NORMAL_MAPPING_TYPE, NormalMappingType.NORMAL);
				}
				
				if (matDef.alphaMapRef && matDef.alphaMap)
					material.setProperty(BasicProperties.ALPHA_MAP, matDef.alphaMap);
				
				if (matDef.alpha < 1.0 || (matDef.alphaMapRef && matDef.alphaMap))
					material.setProperty(BasicProperties.BLENDING, Blending.ALPHA);
				
			}
			
			return material;
		}
	}
}