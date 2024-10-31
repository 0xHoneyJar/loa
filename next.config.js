module.exports = {
  images: {
    remotePatterns: [
      {
        hostname: "cdn.simplehash.com",
      },
      { hostname: "d163aeqznbc6js.cloudfront.net" },
      { hostname: "firebasestorage.googleapis.com" },
    ],
  },
  async redirects() {
    return [
      {
        source: "/mint",
        destination: "https://app.0xhoneyjar.xyz",
        permanent: true,
      },
      {
        source: "/mint/berasvsapes",
        destination: "https://app.0xhoneyjar.xyz/mint/berasvsapes",
        permanent: true,
      },
      {
        source: "/mint/miladysandberas",
        destination: "https://app.0xhoneyjar.xyz/mint/miladysandberas",
        permanent: true,
      },
      {
        source: "/mint/pudgyfrens",
        destination: "https://app.0xhoneyjar.xyz/mint/pudgyfrens",
        permanent: true,
      },
    ];
  },
  webpack: (config) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    return config;
  },
};
