module.exports = {
  images: {
    remotePatterns: [
      {
        hostname: "cdn.simplehash.com",
      },
      { hostname: "d163aeqznbc6js.cloudfront.net" },
    ],
  },
  webpack: (config) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    return config;
  },
};
