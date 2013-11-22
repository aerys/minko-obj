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
	import aerys.minko.render.geometry.stream.format.VertexComponent;
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
			
			if (isNaN(surfaceId))
				surfaceId = 0;
			
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
			
			for (var j : int = faceArray.length; j >= 0; --j)
			{
				if (faceArray[j] == "")
					faceArray.splice(j, 1);
			}
			
			for (var i : uint = 0; i + 2 < faceArray.length; i++)
			{
				var t1 			: Array = faceArray[0].split("/");
				var t2  		: Array = faceArray[i + 1].split("/");
				var t3			: Array = faceArray[i + 2].split("/");
			
				var objItem : ObjItem = new ObjItem(ObjItem.FACE);
			
				
				
				objItem.xyzId 		= [parseInt(t1[0]),	parseInt(t2[0]), parseInt(t3[0])];
				objItem.uvId 		= [parseInt(t1[1]), parseInt(t2[1]), parseInt(t3[1])];
				objItem.normalId 	= [parseInt(t1[2]), parseInt(t2[2]), parseInt(t3[2])];
				objItem.name		= faceString;
			
				_queue.push(objItem);
			}
		}
		
		public function createScene(mtlDoc : MtlDocument)	: Group
		{
			if (!_isLoaded)
				return null;
			
			
			var assets 						: AssetsLibrary 	= new AssetsLibrary();
			var result 						: Group 			= new Group();

			try
			{	
			var currentObjectName 			: String 			= null;
			var numObjItem 					: uint 				= _queue.length;
			var currentGroup 				: Group 			= null;
			var currentMaterial 			: Material 			= null;
			var signatureToIndex			: Dictionary		= new Dictionary();
			var maxIndice 					: uint 				= _positions.length / 3;
			
			var numNormals					: uint 				= _normals.length;
			var numUvs 						: uint 				= _uvs.length;
			
			var surfaceIdToVertexStream		: Dictionary		= new Dictionary();
			var surfaceIdToIndexStream 		: Dictionary		= new Dictionary();
			var surfaceIdToVertexFormat 	: Dictionary		= new Dictionary();
			var surfaceIdToIndex			: Dictionary		= new Dictionary();
			
			var currentSurfaceId 			: int 				= 0;
			
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
							if (mtlDoc == null)
								mtlDoc = new MtlDocument();
							trace(materialName, mtlDoc.materials.hasOwnProperty(materialName));
							currentMaterial = createOrGetMaterial(mtlDoc.materials[materialName], materialName);
							assets.setMaterial(materialName, currentMaterial);
						}
						
						break;
					
					case ObjItem.OBJECT :
						currentObjectName = objItem.name;
						break;
					
					case ObjItem.FACE:
						
						if (surfaceIdToIndexStream[currentSurfaceId] == null)
						{
							surfaceIdToIndexStream[currentSurfaceId] 	= new Vector.<uint>();
							surfaceIdToVertexStream[currentSurfaceId] 	= new Vector.<Number>();
							signatureToIndex[currentSurfaceId] 			= new Dictionary();
							surfaceIdToIndex[currentSurfaceId] 			= 0;
							
							var components : Array = [];
							
							components.push(VertexComponent.XYZ);
							
							if (objItem.uvId[0] != 0 && _uvs.length != 0)
								components.push(VertexComponent.UV);
							if (objItem.normalId[0] != 0 && _normals.length != 0)
								components.push(VertexComponent.NORMAL);
							
							surfaceIdToVertexFormat[currentSurfaceId] = new VertexFormat();
							
							for each (var c : VertexComponent in components)
								VertexFormat(surfaceIdToVertexFormat[currentSurfaceId]).addComponent(c);
						}
						
						var indexStream 	: Vector.<uint> 	= surfaceIdToIndexStream[currentSurfaceId];
						var vertexStream	: Vector.<Number> 	= surfaceIdToVertexStream[currentSurfaceId];
						var format 			: VertexFormat		= surfaceIdToVertexFormat[currentSurfaceId];
						
						var xyz 		: Array 		= objItem.xyzId;
						var normal 		: Array 		= objItem.normalId;
						var uv 			: Array 		= objItem.uvId;
						
						var vertice0Id	: Vector.<uint> = new Vector.<uint>(); vertice0Id.push(xyz[0], uv[0], normal[0]); 
						var vertice1Id	: Vector.<uint> = new Vector.<uint>(); vertice1Id.push(xyz[1], uv[1], normal[1]);
						var vertice2Id 	: Vector.<uint> = new Vector.<uint>(); vertice2Id.push(xyz[2], uv[2], normal[2]);
						
						var signature0 	: uint 			= CRC32.computeForUintVector(vertice0Id);
						var signature1	: uint 			= CRC32.computeForUintVector(vertice1Id);
						var signature2 	: uint 			= CRC32.computeForUintVector(vertice2Id);
						
						var vertexIds	: Array = [vertice0Id, vertice1Id, vertice2Id];
						var signatures 	: Array = [signature0, signature1, signature2];
						var indexList 	: Array = [0, 0, 0];
						
						var index0 	: uint = 0;
						var index1 	: uint = 0;
						var index2 	: uint = 0;
							
						for (var j : uint = 0; j < 3; ++j)
						{
							if (signatureToIndex[currentSurfaceId][signatures[j]] != null)
								indexList[j] = signatureToIndex[currentSurfaceId][signatures[j]];
							else
							{
								var verticeId 	: Vector.<uint> = vertexIds[j];
								var xyzIndex 	: uint 			= verticeId[0] - 1;
								var uvIndex 	: uint 			= verticeId[1] - 1;
								var nIndex 		: uint 			= verticeId[2] - 1;
								
								if (verticeId.length == 0 || verticeId[1] == 0)
									uvIndex = 0;
								
								vertexStream.push(_positions[uint(xyzIndex * 3)], _positions[uint(xyzIndex * 3 + 1)], _positions[uint(xyzIndex * 3 + 2)]);
								
								if (format.hasComponent(VertexComponent.UV))
								{
									if (uvIndex * 2 >= _uvs.length)
										vertexStream.push(0, 0);
									else
										vertexStream.push(_uvs[uint(uvIndex * 2)], _uvs[uint(uvIndex * 2 + 1)]);
								}
								
								if (format.hasComponent(VertexComponent.NORMAL))
								{
									if (nIndex * 3 >= _normals.length)
										vertexStream.push(1, 1, 0);
									else
										vertexStream.push(_normals[uint(nIndex * 3)], _normals[uint(nIndex * 3 + 1)], _normals[uint(nIndex * 3 + 2)]);
								}
								indexList[j] = surfaceIdToIndex[currentSurfaceId]++;
								signatureToIndex[currentSurfaceId][signatures[j]] = indexList[j];
							}
						}
						
						indexStream.push(indexList[0], indexList[2], indexList[1]);
						
						if (i == numObjItem - 1 || (_queue[i + 1].type != ObjItem.FACE && _queue[i + 1].type != ObjItem.SURFACE || _queue[i + 1].type == ObjItem.SURFACE && _queue[i + 2].type == ObjItem.MTL))
						{
							if (currentGroup == null)
								currentGroup = result;
							
							for (var key : * in surfaceIdToIndexStream)
							{
								var meshes : Vector.<Mesh> = buildMeshes(surfaceIdToIndexStream[key], surfaceIdToVertexStream[key], surfaceIdToVertexFormat[key], currentMaterial, currentObjectName + key);
							
								for each (var mesh : Mesh in meshes)
								{
									currentGroup.addChild(mesh);
									assets.setGeometry(mesh.name + "_geometry", mesh.geometry);
								}
							}
							currentObjectName 		= null;
							surfaceIdToIndexStream 	= new Dictionary();
							surfaceIdToVertexStream = new Dictionary();
							surfaceIdToVertexFormat = new Dictionary();
							signatureToIndex 		= new Dictionary();
							surfaceIdToIndex		= new Dictionary();
						}
						
						break;
					
					case ObjItem.SURFACE:
						currentSurfaceId = objItem.surfaceId;
						break;
				}
			}
			}
			catch (e : Error)
			{
				Minko.log(DebugLevel.PLUGIN_ERROR, "non valid obj file");
				
				result = new Group();
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
				
				changeHandedness(vertexStreams[i], vertexFormat, indexStreams[i]);
				
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
		
		private function changeHandedness(vertexData	: ByteArray, 
										  vertexFormat	: VertexFormat, 
										  indexData		: ByteArray) : void
		{
			changeVertexHandedness(vertexData, vertexFormat);
			changeIndexWinding(indexData);
		}
		
		private function changeVertexHandedness(vertexData		: ByteArray, 
												vertexFormat	: VertexFormat) : void
		{
			var vertexSize		: uint	= vertexFormat.numBytesPerVertex;
			
			if (vertexSize == 0)
				return;
			
			var numVertices		: uint	= vertexData.length / vertexSize;
			var offsetXYZ		: int 	= vertexFormat.hasComponent(VertexComponent.XYZ)		? vertexFormat.getBytesOffsetForComponent(VertexComponent.XYZ)		: -1;
			var offsetNormal	: int	= vertexFormat.hasComponent(VertexComponent.NORMAL)		? vertexFormat.getBytesOffsetForComponent(VertexComponent.NORMAL)	: -1;
			var offsetTangent	: int	= vertexFormat.hasComponent(VertexComponent.TANGENT)	? vertexFormat.getBytesOffsetForComponent(VertexComponent.TANGENT)	: -1;
			var offsetTexCoords	: int	= vertexFormat.hasComponent(VertexComponent.UV)			? vertexFormat.getBytesOffsetForComponent(VertexComponent.UV)		: -1;
			
			var vertexStartPos	: uint 		= 0;
			var componentValue	: Number	= 0.0;
			
			for (var vertexId:uint = 0; vertexId < numVertices; ++vertexId)
			{
				// x -> -x
				if (offsetXYZ >= 0)
				{
					vertexData.position = vertexStartPos + offsetXYZ;
					componentValue		= vertexData.readFloat();
					vertexData.position	-= 4;
					vertexData.writeFloat(-componentValue);
				}

				// nx -> -nx
				if (offsetNormal >= 0)
				{
					vertexData.position = vertexStartPos + offsetNormal;
					componentValue		= vertexData.readFloat();
					vertexData.position	-= 4;
					vertexData.writeFloat(-componentValue);
				}
				
				// tx -> -tx
				if (offsetTangent >= 0)
				{
					vertexData.position = vertexStartPos + offsetTangent;
					componentValue		= vertexData.readFloat();
					vertexData.position	-= 4;
					vertexData.writeFloat(-componentValue);
				}
				
				// v -> 1 - v
				if (offsetTexCoords >= 0)
				{
					vertexData.position = vertexStartPos + offsetTexCoords + 4;
					componentValue		= vertexData.readFloat();
					vertexData.position	-= 4;
					vertexData.writeFloat(1.0 - componentValue);
				}
				
				vertexStartPos += vertexSize;
			}
			
			vertexData.position = 0;
		}
		
		private function changeIndexWinding(indexData : ByteArray) : void
		{
			var length	: uint	= indexData.length;
			var offset	: uint	= 0;
			
			indexData.position = offset;
			
			while (offset < length)
			{
				var idx1	: uint	= indexData.readUnsignedShort();
				var idx2	: uint	= indexData.readUnsignedShort();
				var idx3	: uint	= indexData.readUnsignedShort();
				
				indexData.position	-= 4;
				
				indexData.writeShort(idx3);
				indexData.writeShort(idx2);
				
				offset += 6;
			}
			
			indexData.position = 0;
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
					material.setProperty(PhongProperties.SPECULAR, toRGBA(matDef.specularR, matDef.specularG, matDef.specularB, 1));
				
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
			else
			{
				material.diffuseColor = 0xFFFFFFFF;
			}
			
			return material;
		}
	}
}