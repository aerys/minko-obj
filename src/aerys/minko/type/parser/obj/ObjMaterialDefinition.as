package aerys.minko.type.parser.obj
{
	import aerys.minko.render.resource.texture.TextureResource;
	
	import mx.controls.Text;

	public final class ObjMaterialDefinition
	{
		public var ambientR			: Number;
		public var ambientG			: Number;
		public var ambientB			: Number;
		
		public var diffuseR			: Number;
		public var diffuseG			: Number;
		public var diffuseB			: Number;
		
		public var specularR		: Number;
		public var specularG		: Number;
		public var specularB		: Number;
		
		public var alpha			: Number		= 1.;
		public var shininess		: Number;
		public var illumination		: int;
		
		public var diffuseMapRef	: String;
		public var diffuseMap		: TextureResource;
		public var alphaMask		: TextureResource;
		public var alphaMapRef		: String;
		public var lightMap			: TextureResource;
		public var lightMapRef		: String;
		public var specularMap		: TextureResource;
		public var specularMapRef	: String;
		public var normalMap		: TextureResource;
		public var normalMapRef		: String;
	}
}