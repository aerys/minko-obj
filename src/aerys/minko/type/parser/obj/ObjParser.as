package aerys.minko.type.parser.obj
{
	import aerys.minko.scene.node.IScene;
	import aerys.minko.scene.node.group.StyleGroup;
	import aerys.minko.scene.node.mesh.IMesh;
	import aerys.minko.scene.node.mesh.Mesh;
	import aerys.minko.type.parser.IParser;
	import aerys.minko.type.parser.ParserOptions;
	import aerys.minko.type.stream.IndexStream;
	import aerys.minko.type.stream.VertexStream;
	import aerys.minko.type.stream.format.VertexComponent;
	import aerys.minko.type.stream.format.VertexFormat;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.getTimer;
	
	/**
	 * 
	 * @author Romain Gilliotte <romain.gilliotte@aerys.in>
	 * 
	 */	
	public class ObjParser extends EventDispatcher implements IParser
	{
		private static const INDEX_LIMIT				: uint						= 524270;
		private static const VERTEX_LIMIT				: uint						= 5000;
		private static const MERGE_DUPLICATED_VERTICES	: Boolean					= true;
		private static const TMP_BUFFER					: Vector.<Vector.<uint>>	= new Vector.<Vector.<uint>>(3);
		
		private static const TEN_POWERS					: Vector.<Number> = Vector.<Number>([
			1, 0.1, 0.01, 0.001, 0.0001, 0.00001, 0.000001,
			0.0000001, 0.00000001, 0.000000001, 0.0000000001,
			0.00000000001, 0.000000000001, 0.0000000000001
		]);
		
		
		private var _data					: Vector.<IScene>;
		private var _options				: ParserOptions;
		
		private var _currentLine			: uint;
		
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
			try
			{
				_options = options;
				reset();
				
				var t : uint = getTimer();
				readData(data);
				trace('vertices and indexes parsing:', getTimer() - t);
				
				createGroups();
				
				trace('--------------------');
				dispatchEvent(new Event(Event.COMPLETE));
				
				return true;
			}
			catch (e : Error)
			{
			}
			return false;
		}
		
		private function reset() : void
		{
			_data.length				= 0;
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
					case 0x0d: // "\r"
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
						throw new Error('Malformed OBJ file');
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
					throw new Error('Malformed OBJ file');
				}
			}
			
		}
		
		private function createGroups() : void
		{
			var numMeshes : uint = _groupNames.length;
			
			for (var meshId : uint = 0; meshId < numMeshes; ++meshId)
			{
				var group : StyleGroup = new StyleGroup();
				
				group.name = _groupNames[meshId];
				
				if (_options.loadTextures)
				{
					var material : IScene = _options.loadFunction(new URLRequest(_groupNames[meshId]));
					
					if (material != null)
						material = _options.replaceNodeFunction(material);
					
					if (material != null)
						group.addChild(material);
				}
				
				if (_options.loadMeshes)
				{
					var meshs		: Vector.<IMesh>	= createMeshs(meshId);
					var meshsCount	: uint				= meshs.length;
					
					for (var i : uint = 0; i < meshsCount; ++i)
					{
						if (meshs[i] != null)
							meshs[i] = _options.replaceNodeFunction(meshs[i]);
					
						if (meshs[i] != null)
							group.addChild(meshs[i]);
					}
				}
				
				var final : IScene = _options.replaceNodeFunction(group);
				
				if (final != null)
					_data.push(final);
			}
		}
		
		private function createVertexFormat(meshId : uint) : VertexFormat
		{
			var positionCounts	: uint = _groupFacesPositions[meshId].length;
			var uvCounts		: uint = _groupFacesUvs[meshId].length;
			var normalsCounts	: uint = _groupFacesNormals[meshId].length;
			var numIndices		: uint = Math.max(positionCounts, uvCounts, normalsCounts);
			
			var vertexFormat	: VertexFormat = new VertexFormat();
			
			if (positionCounts != numIndices)
				throw new Error('Invalid OBJ file');
			
			vertexFormat.addComponent(VertexComponent.XYZ);
			
			if (uvCounts != 0)
			{
				if (uvCounts != numIndices)
					throw new Error('Invalid OBJ file');
				
				vertexFormat.addComponent(VertexComponent.UV);
			}
			
			/*if (normalsCounts != 0)
			{
				if (normalsCounts != numIndices)
					throw new Error('Invalid OBJ file');
				
				vertexFormat.addComponent(VertexComponent.NORMAL);
			}*/
			
			return vertexFormat;
		}
		
		private function createMeshs(meshId : uint) : Vector.<IMesh>
		{
			var format			: VertexFormat		= createVertexFormat(meshId);
			var indexBuffer		: Vector.<uint>		= new Vector.<uint>();
			var vertexBuffer	: Vector.<Number>	= new Vector.<Number>();
			
			var t1 : uint = getTimer();
			fillBuffers(meshId, format, indexBuffer, vertexBuffer);
			
			
			var result			: Vector.<IMesh>	= new Vector.<IMesh>();
			var indexStream		: IndexStream;
			var vertexStream	: VertexStream;
			
			if (indexBuffer.length < INDEX_LIMIT && vertexBuffer.length / format.dwordsPerVertex < VERTEX_LIMIT)
			{
				indexStream		= new IndexStream(_options.defaultIndexStreamUsage, indexBuffer, 0);
				vertexStream	= new VertexStream(_options.defaultVertexStreamUsage, format, vertexBuffer);
				
				result.push(new Mesh(vertexStream, indexStream));
			}
			else
			{
				var t2 : uint = getTimer();
				var indexBuffers	: Vector.<Vector.<uint>>	= new Vector.<Vector.<uint>>();
				var vertexBuffers	: Vector.<Vector.<Number>>	= new Vector.<Vector.<Number>>();
				
				splitBuffers(indexBuffer, vertexBuffer, format, indexBuffers, vertexBuffers);
				
				var numMeshes	: uint	= indexBuffers.length;
				
				for (var i : uint = 0; i < numMeshes; ++i)
				{
					indexStream	= new IndexStream(
						_options.defaultIndexStreamUsage,
						indexBuffers[i],
						0
					);
					
					vertexStream = new VertexStream(
						_options.defaultVertexStreamUsage,
						format,
						vertexBuffers[i]
					);
					
					result.push(new Mesh(vertexStream, indexStream));
				}
			}
			
			return result;
		}
		
		private function fillBuffers(meshId		: uint,
									 format		: VertexFormat,
									 indexData	: Vector.<uint>, 
									 vertexData	: Vector.<Number>) : void
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
				
				var positionIndex : int = 3 * (positionIndices[indexId] - 1);
				tmpVertex[tmpVertexComponentId++] = _positions[positionIndex];
				tmpVertex[tmpVertexComponentId++] = _positions[int(positionIndex + 1)];
				tmpVertex[tmpVertexComponentId++] = _positions[int(positionIndex + 2)];
				
				if (useUVs)
				{
					var uvIndex : int = 2 * (uvsIndices[indexId] - 1);
					if (uvIndex >= 0)
					{
						tmpVertex[tmpVertexComponentId++] = _uvs[uvIndex];
						tmpVertex[tmpVertexComponentId++] = _uvs[int(uvIndex + 1)];
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
				
				if (MERGE_DUPLICATED_VERTICES)
				{
					var joinedVertex	: String	= tmpVertex.join('|');
					
					if (!verticesToIndex.hasOwnProperty(joinedVertex))
					{
						for (tmpVertexComponentId = 0; tmpVertexComponentId < tmpVertexDwords; ++tmpVertexComponentId)
							vertexData.push(tmpVertex[tmpVertexComponentId]);
					
						verticesToIndex[joinedVertex] = vertexIndex = currentNumVertices++;
					}
					else
					{
						vertexIndex = verticesToIndex[joinedVertex];
					}
					indexData.push(vertexIndex);
				}
				else
				{
					for (tmpVertexComponentId = 0; tmpVertexComponentId < tmpVertexDwords; ++tmpVertexComponentId)
						vertexData.push(tmpVertex[tmpVertexComponentId]);
					indexData.push(currentNumVertices++);
				}
			}
		}
		
		private function splitBuffers(indexData			: Vector.<uint>,
									  vertexData		: Vector.<Number>,
									  vertexFormat		: VertexFormat,
									  newIndexDatas		: Vector.<Vector.<uint>>,
									  newVertexDatas	: Vector.<Vector.<Number>>) : void
		{
			while (indexData.length != 0)
			{
				var dwordsPerVertex		: uint				= vertexFormat.dwordsPerVertex;
				var indexDataLength		: uint				= indexData.length;
				
				// new buffers
				var partialVertexData	: Vector.<Number>	= new Vector.<Number>();
				var partialIndexData	: Vector.<uint>		= new Vector.<uint>();
				
				// local variables
				var oldVertexIds		: Vector.<int>		= new Vector.<int>(3, true);
				var newVertexIds		: Vector.<int>		= new Vector.<int>(3, true);
				var newVertexNeeded		: Vector.<Boolean>	= new Vector.<Boolean>(3, true);
				
				var usedVerticesDic		: Dictionary		= new Dictionary();		// dico de correspondance entre anciens et nouveaux indices
				var usedVerticesCount	: uint				= 0;					// taille du tableau ci dessus
				var usedIndicesCount	: uint				= 0;					// quantitee d'indices utilises pour l'instant
				var neededVerticesCount	: uint;
				
				// iterators & limits
				var localVertexId		: uint;
				var dwordId				: uint;
				var dwordIdLimit		: uint;
				
				while (usedIndicesCount < indexDataLength)
				{
					// check si le triangle suivant rentrera dans l'index buffer
					var remainingIndexes	: uint		= INDEX_LIMIT - usedIndicesCount;
					if (remainingIndexes < 3)
						break;
					
					// check si le triangle suivant rentre dans le vertex buffer
					var remainingVertices	: uint		= VERTEX_LIMIT - usedVerticesCount;
					
					neededVerticesCount = 0;
					for (localVertexId = 0; localVertexId < 3; ++localVertexId)
					{
						var t : uint = getTimer();	
						oldVertexIds[localVertexId]		= indexData[uint(usedIndicesCount + localVertexId)];
						
						var tmp : Object = usedVerticesDic[oldVertexIds[localVertexId]];
						
						newVertexNeeded[localVertexId]	= tmp == null;
						newVertexIds[localVertexId]		= uint(tmp);
						
						if (newVertexNeeded[localVertexId])
							++neededVerticesCount;
					}
					
					if (remainingVertices < neededVerticesCount)
						break;
					
					// ca rentre, on insere le triangle avec les donnees qui vont avec
					for (localVertexId = 0; localVertexId < 3; ++localVertexId)
					{
						
						if (newVertexNeeded[localVertexId])
						{
							// on copie le vertex dans le nouveau tableau
							dwordId			= oldVertexIds[localVertexId] * dwordsPerVertex;
							dwordIdLimit	= dwordId + dwordsPerVertex;
							for (; dwordId < dwordIdLimit; ++dwordId)
								partialVertexData.push(vertexData[dwordId]);
							
							// on met a jour l'id dans notre variable temporaire pour remplir le nouvel indexData
							newVertexIds[localVertexId] = usedVerticesCount;
							
							// on note son ancien id dans le tableau temporaire
							usedVerticesDic[oldVertexIds[localVertexId]] = usedVerticesCount++;
						}
						
						partialIndexData.push(newVertexIds[localVertexId]);
					}
					
					// ... on incremente le compteur
					usedIndicesCount += 3;
					
					// on fait des assertions, sinon ca marchera jamais
//					if (usedIndicesCount != partialIndexData.length)
//						throw new Error('');
//					
//					if (usedVerticesCount != usedVertices.length)
//						throw new Error('');
//					
//					if (usedVerticesCount != partialVertexData.length / dwordsPerVertex)
//						throw new Error('');
				}
				
				newIndexDatas.push(partialIndexData);
				newVertexDatas.push(partialVertexData);
				
				indexData.splice(0, usedIndicesCount);
			}
		}
		
	}
}