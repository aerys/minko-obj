package aerys.minko.type.parser.obj
{
	import aerys.minko.render.resource.texture.TextureResource;

	public final class ObjMaterial
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
		
		public var diffuseMapRef	: String;
		
		public var illumination		: int;
		
		public var diffuseMap		: TextureResource;
	}
}