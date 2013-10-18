package aerys.minko.type.parser.obj
{
	import aerys.minko.render.resource.texture.TextureResource;


	public final class ObjMaterialDefinition
	{
		public var ambientExists	: Boolean		= false;
		public var ambientR			: Number		= 1.;
		public var ambientG			: Number		= 1.;
		public var ambientB			: Number		= 1.;
		
		public var diffuseExists	: Boolean		= false;
		public var diffuseR			: Number		= 1.;
		public var diffuseG			: Number		= 1.;
		public var diffuseB			: Number		= 1.;
		
		public var specularExists	: Boolean		= false;
		public var specularR		: Number		= 1.;
		public var specularG		: Number		= 1.;
		public var specularB		: Number		= 1.;
		
		public var alpha			: Number		= 1.;
		public var shininess		: Number		= 1.;
		public var illumination		: int			= 1;
		
		public var diffuseMapRef	: String;
		public var diffuseMap		: TextureResource;
		public var alphaMap			: TextureResource;
		public var alphaMapRef		: String;
		public var lightMap			: TextureResource;
		public var lightMapRef		: String;
		public var specularMap		: TextureResource;
		public var specularMapRef	: String;
		public var normalMap		: TextureResource;
		public var normalMapRef		: String;
	}
}