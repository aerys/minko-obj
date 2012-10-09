package aerys.minko.type.parser.obj
{
	import aerys.minko.Minko;
	import aerys.minko.render.geometry.Geometry;
	import aerys.minko.render.geometry.GeometrySanitizer;
	import aerys.minko.render.geometry.stream.IVertexStream;
	import aerys.minko.render.geometry.stream.IndexStream;
	import aerys.minko.render.geometry.stream.VertexStream;
	import aerys.minko.render.geometry.stream.format.VertexComponent;
	import aerys.minko.render.geometry.stream.format.VertexFormat;
	import aerys.minko.render.material.basic.BasicMaterial;
	import aerys.minko.scene.node.Group;
	import aerys.minko.scene.node.Mesh;
	import aerys.minko.type.enum.FrustumCulling;
	import aerys.minko.type.enum.TriangleCulling;
	import aerys.minko.type.error.obj.ObjError;
	import aerys.minko.type.loader.ILoader;
	import aerys.minko.type.loader.parser.ParserOptions;
	import aerys.minko.type.log.DebugLevel;
	import aerys.minko.type.math.Frustum;
	
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.Endian;
	import flash.utils.getTimer;

	public final class ObjDocument
	{
		private static const INDEX_LIMIT				: uint						= 524270;
		private static const VERTEX_LIMIT				: uint						= 65535;
		private static const TMP_BUFFER					: Vector.<Vector.<uint>>	= new Vector.<Vector.<uint>>(3);
		
		private static const TEN_POWERS					: Vector.<Number> = Vector.<Number>([
			1, 0.1, 0.01, 0.001, 0.0001, 0.00001, 0.000001,
			0.0000001, 0.00000001, 0.000000001, 0.0000000001,
			0.00000000001, 0.000000000001, 0.0000000000001
		]);

		private var _data								: Group;
		private var _options							: ParserOptions;
		
		private var _currentLine						: uint;
		
		private var _positions							: Vector.<Number>;
		private var _uvs								: Vector.<Number>;
		private var _normals							: Vector.<Number>;
		
		private var _groupNames							: Vector.<String>;
		private var _groupFacesPositions				: Vector.<Vector.<uint>>;
		private var _groupFacesUvs						: Vector.<Vector.<uint>>;
		private var _groupFacesNormals					: Vector.<Vector.<uint>>;
		
		private var _isLoaded							: Boolean;
		
		private var _mtlFiles							: Vector.<String>;
		
		public function get isLoaded() : Boolean
		{
			return _isLoaded;
		}
		
		public function get MtlFiles() : Vector.<String>
		{
			return _mtlFiles;
		}
		
		public function ObjDocument()
		{
			_data					= new Group();
			
			_positions				= new Vector.<Number>();
			_uvs					= new Vector.<Number>();
			_normals				= new Vector.<Number>();
			
			_groupNames				= new Vector.<String>();
			_groupFacesPositions	= new Vector.<Vector.<uint>>();
			_groupFacesUvs			= new Vector.<Vector.<uint>>();
			_groupFacesNormals		= new Vector.<Vector.<uint>>();
		
			_mtlFiles				= new Vector.<String>();
			
			_isLoaded				= false;
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
			
			_groupNames.length			= 0;
			_groupFacesPositions.length	= 0;
			_groupFacesUvs.length		= 0;
			_groupFacesNormals.length	= 0;
		}
		
		private function readData(data : ByteArray) : void
		{
			data.position = 0;
			
			var currentMaterialId : uint = 0;
			while (data.position != data.length)
			{
				var char : uint;
				switch (char = data.readUnsignedByte())
				{
					case 0x76: // "v"
						switch (data.readUnsignedByte())
						{
							case 0x20: // " "
								eatSpaces(data);
								parseFloats(data, 3, _positions);
								break;
							
							case 0x6e: // "n"
								eatSpaces(data);
								parseFloats(data, 3, _normals);
								
								break;
							
							case 0x74: // "t"
								eatSpaces(data);
								parseFloats(data, 2, _uvs);
								break;
							
							default:
								throw new ObjError('Line ' + _currentLine + ': unknown vertex declaration');
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
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "usemtl"?');
						
						skipChars(data, 1);
						currentMaterialId = retrieveMaterial(data);
						break;
					
					case 0x6d: // "m"
						if (data.readUTFBytes(5) != 'tllib')
							throw new ObjError('Line ' + _currentLine + ': unknown definition, did you mean "mtllib"?');
						
						parseMtllib(data); // we ignore mtllib instructions
						break;
					
					case 0x23: // "#"
					case 0x73: // "s"
					case 0x0d: // "\r"
						gotoNextLine(data); // we ignore smoothing group instructions
						break;
					
					case 0x0a: // "\n"
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
		
		private function retrieveMaterial(data : ByteArray) : uint
		{
			var matName	: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					matName += char;
			}
			
			var materialId : int = _groupNames.indexOf(matName);
			if (materialId == -1)
			{
				materialId = _groupNames.length;
				
				_groupNames.push(matName)
				_groupFacesPositions.push(new Vector.<uint>());
				_groupFacesUvs.push(new Vector.<uint>());
				_groupFacesNormals.push(new Vector.<uint>());
			}
			++_currentLine;
			return materialId;
		}
		
		private function parseMtllib(data : ByteArray) : void
		{
			var mtl		: String = "";
			var char	: String;
			
			while ((char = data.readUTFBytes(1)) != '\n')
			{
				if (char != '\r')
					mtl += char;
			}
			
			_mtlFiles.push(mtl);
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
		
		private function parseFace(data			: ByteArray, 
								   materialId	: uint) : void
		{
			var currentIndex			: uint = 0;
			var numVertices				: uint = 0;
			
			// 0: position, 1: uv, 2: normal
			var currentIndexSemantic	: uint = 0;
			
			if (materialId == 0 && _groupFacesPositions.length == 0)
			{
				_groupNames.push('default_material')
				_groupFacesPositions.push(new Vector.<uint>());
				_groupFacesUvs.push(new Vector.<uint>());
				_groupFacesNormals.push(new Vector.<uint>());
			}
			
			TMP_BUFFER[0] = _groupFacesPositions[materialId];
			TMP_BUFFER[1] = _groupFacesUvs[materialId];
			TMP_BUFFER[2] = _groupFacesNormals[materialId];
			
			var lastWasNumber : Boolean = false;
			while (true)
			{
				var readChar		: uint		= data.readUnsignedByte();
				var processingOk	: Boolean	= true;
				
				if (readChar >= 0x30 && readChar < 0x3a) // ['0'-'9']
				{
					currentIndex = 10 * currentIndex + readChar - 0x30;
					lastWasNumber = true;
				}
				else if (readChar == 0x2f) // "/"
				{
					TMP_BUFFER[currentIndexSemantic].push(currentIndex);
					currentIndex = 0;
					++currentIndexSemantic;
					lastWasNumber = false;
				}
				else if (readChar == 0x20 || readChar == 0x0d || readChar == 0x0a) // " " || "\r" || "\n"
				{
					if (lastWasNumber)
					{
						// push new point
						TMP_BUFFER[currentIndexSemantic].push(currentIndex);
						currentIndex = 0;
						currentIndexSemantic = 0;
						++numVertices;
						lastWasNumber = false;
						
						// triangulate
						if (numVertices > 3)
							for (var i : uint = 0; i < 3; ++i)
								if (TMP_BUFFER[i].length != 0)
									TMP_BUFFER[i].push(
										TMP_BUFFER[i][TMP_BUFFER[i].length - numVertices],
										TMP_BUFFER[i][TMP_BUFFER[i].length - 2]
									);
					}
				}
				else
				{
					processingOk = false;
					lastWasNumber = false;
				}
				
				if (readChar == 0x0d) // "\r"
				{
					gotoNextLine(data);
					break;
				}
				else if (readChar == 0x0a) // "\n"
				{
					++_currentLine;
					break;
				}
				else if (!processingOk)
				{
					throw new ObjError('Line ' + _currentLine + ': invalid face formating');
				}
			}
		}
		
		public function createScene(mtlDoc : MtlDocument)	: Group
		{
			if (!_isLoaded)
			{
				return null;
			}
			
			var numMeshes	: uint		= _groupNames.length;
			var result		: Group 	=  new Group();
			
			for (var meshId : uint = 0; meshId < numMeshes; ++meshId)
			{
				var group : Group = new Group();
				
				group.name = _groupNames[meshId];
				if (mtlDoc)
				{
					var matDef : ObjMaterial = mtlDoc.materials[group.name];
				}

				var meshs		: Vector.<Mesh>	= createMeshs(meshId, matDef);
				var meshsCount	: uint				= meshs.length;
				
				for (var i : uint = 0; i < meshsCount; ++i)
				{
					if (meshs[i] != null && meshs[i].geometry.getVertexStream(0).numVertices != 0 && meshs[i].geometry.indexStream.length != 0)
					{
						group.addChild(meshs[i]);
					}
				}
			}
				
			if (group != null)
			{
				result.addChild(group);
			}
				
			return result;
		}
		
		private function createVertexFormat(meshId : uint) : VertexFormat
		{
			var positionCounts	: uint = _groupFacesPositions[meshId].length;
			var uvCounts		: uint = _groupFacesUvs[meshId].length;
			var normalsCounts	: uint = _groupFacesNormals[meshId].length;
			var numIndices		: uint = Math.max(positionCounts, uvCounts, normalsCounts);
			
			var vertexFormat	: VertexFormat = new VertexFormat();
			
			if (positionCounts != numIndices)
				throw new ObjError('OBJ error: number of positions and indices do not match');
			
			vertexFormat.addComponent(VertexComponent.XYZ);
			
			if (uvCounts != 0)
			{
				if (uvCounts != numIndices)
					throw new ObjError('OBJ error: number of UVs and indices do not match');
				
				vertexFormat.addComponent(VertexComponent.UV);
			}

			if (normalsCounts != 0)
			{
				if (normalsCounts != numIndices)
					throw new ObjError('OBJ error: number of normals and indices do not match');
				
				vertexFormat.addComponent(VertexComponent.NORMAL);
			}

			return vertexFormat;
		}
		
		private function createMeshs(meshId			: uint,
									 matDef			: ObjMaterial) : Vector.<Mesh>
		{
			var format			: VertexFormat		= createVertexFormat(meshId);
			var indexBuffer		: Vector.<uint>		= new Vector.<uint>();
			var vertexBuffer	: ByteArray			= new ByteArray();
			vertexBuffer.endian = Endian.LITTLE_ENDIAN;
			
			fillBuffers(meshId, format, indexBuffer, vertexBuffer);
			
			var result			: Vector.<Mesh>	= new Vector.<Mesh>();
			var indexStream		: IndexStream;
			var vertexStream	: VertexStream;
			var vertexStreams 	: Vector.<IVertexStream>;
			var geometry		: Geometry;
			var material		: BasicMaterial;
			var mesh			: Mesh;
			var color			: uint = 0;
			
			indexBuffer.reverse();
			if (indexBuffer.length < INDEX_LIMIT && vertexBuffer.length / format.numComponents < VERTEX_LIMIT)
			{
				indexStream		= IndexStream.fromVector(_options.indexStreamUsage, indexBuffer);
				vertexBuffer.position = 0;
				vertexStream	= new VertexStream(_options.vertexStreamUsage, format, vertexBuffer);
				
				vertexStreams = new Vector.<IVertexStream>(1);
				vertexStreams[0] = vertexStream;
				geometry = new Geometry(vertexStreams, indexStream);
				material = new BasicMaterial();
				if (matDef)
				{
					material.alphaThreshold = matDef.alpha;
					material.diffuseMap = matDef.diffuseMap;
					color = (matDef.diffuseR * 255);
					color = (color << 8) + (matDef.diffuseG);
					color = (color << 8) + (matDef.diffuseB);
					material.diffuseColor = color;
				}
				
				mesh = new Mesh(geometry, material, "");
				mesh.frustumCulling = FrustumCulling.DISABLED;
				result.push(mesh);
			}
			else
			{
				var indexBuffers	: Vector.<ByteArray>		= new Vector.<ByteArray>();
				var vertexBuffers	: Vector.<ByteArray>		= new Vector.<ByteArray>();
				
				GeometrySanitizer.splitBuffers(vertexBuffer, indexBuffer, vertexBuffers, indexBuffers, format.numBytesPerVertex);
				var numMeshes	: uint	= indexBuffers.length;
				
				for (var i : uint = 0; i < numMeshes; ++i)
				{
					indexStream = new IndexStream(_options.indexStreamUsage,
						indexBuffers[i]);
					
					vertexStream = new VertexStream(
						_options.vertexStreamUsage,
						format,
						vertexBuffers[i]
					);
					
					vertexStreams = new Vector.<IVertexStream>(1);
					vertexStreams[0] = vertexStream;
					geometry = new Geometry(vertexStreams, indexStream);
					material = new BasicMaterial();				
					if (matDef)
					{
						material.alphaThreshold = matDef.alpha;
						material.diffuseMap = matDef.diffuseMap;
						color = (matDef.diffuseR * 255);
						color = (color << 8) + (matDef.diffuseG);
						color = (color << 8) + (matDef.diffuseB);
						material.diffuseColor = color;
					}
					
					mesh = new Mesh(geometry, material, "");
					mesh.frustumCulling = FrustumCulling.DISABLED;
					result.push(mesh);
				}
			}
			
			return result;
		}
		
		private function fillBuffers(meshId		: uint,
									 format		: VertexFormat,
									 indexData	: Vector.<uint>, 
									 vertexData	: ByteArray) : void
		{
			var useUVs					: Boolean				= format.hasComponent(VertexComponent.UV);
			var useNormals				: Boolean				= format.hasComponent(VertexComponent.NORMAL);
			var dwordsPerVertex			: uint					= 3 + 2 * uint(useUVs) + 3 * uint(useNormals);
			
			var vertexIndex				: uint;
			var verticesToIndex			: Object				= new Object();
			
			var tmpVertex				: Vector.<Number>		= new Vector.<Number>();
			var tmpVertexComponentId	: uint					= 0;
			var tmpVertexDwords			: uint					= dwordsPerVertex;
			
			var positionIndices			: Vector.<uint>			= _groupFacesPositions[meshId];
			var uvsIndices				: Vector.<uint>			= _groupFacesUvs[meshId];
			var normalIndices			: Vector.<uint>			= _groupFacesNormals[meshId];
			
			var numIndices				: uint					= positionIndices.length;
			var currentNumVertices		: uint					= 0;
			
			for (var indexId : uint = 0; indexId < numIndices; ++indexId)
			{
				tmpVertexComponentId  = 0;
				
				var positionIndex : uint = 3 * (positionIndices[indexId] - 1);
				tmpVertex[tmpVertexComponentId++] = _positions[positionIndex];
				tmpVertex[tmpVertexComponentId++] = _positions[int(positionIndex + 1)];
				tmpVertex[tmpVertexComponentId++] = _positions[int(positionIndex + 2)];
				
				if (useUVs)
				{
					var uvIndex : int = 2 * (uvsIndices[indexId] - 1);
					if (uvIndex >= 0)
					{
						tmpVertex[tmpVertexComponentId++] = _uvs[uvIndex];
						tmpVertex[tmpVertexComponentId++] = 1 - _uvs[int(uvIndex + 1)];
					}
					else
					{
						tmpVertex[tmpVertexComponentId++] = 0;
						tmpVertex[tmpVertexComponentId++] = 0;
					}
				}
				
				if (useNormals)
				{
					var normalIndex : int = 3 * (normalIndices[indexId] - 1);
					tmpVertex[tmpVertexComponentId++] = _normals[normalIndex];
					tmpVertex[tmpVertexComponentId++] = _normals[int(normalIndex + 1)];
					tmpVertex[tmpVertexComponentId++] = _normals[int(normalIndex + 2)];
				}
				
				var joinedVertex	: String	= tmpVertex.join('|');
				if (!verticesToIndex.hasOwnProperty(joinedVertex))
				{
					for (tmpVertexComponentId = 0; tmpVertexComponentId < tmpVertexDwords; ++tmpVertexComponentId)
						vertexData.writeFloat(tmpVertex[tmpVertexComponentId]);
					
					verticesToIndex[joinedVertex] = vertexIndex = currentNumVertices++;
				}
				else
				{
					vertexIndex = verticesToIndex[joinedVertex];
				}
				
				indexData.push(vertexIndex);
			}
		}
	}
}