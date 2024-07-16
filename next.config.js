module.exports = {
  images: {
    domains: ["cdn.simplehash.com", "d163aeqznbc6js.cloudfront.net"],
  },
  webpack: (config) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    return config;
  },
};
