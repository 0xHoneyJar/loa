module.exports = {
  images: {
    remotePatterns: [
      {
        hostname: "cdn.simplehash.com",
      },
      { hostname: "d163aeqznbc6js.cloudfront.net" },
      { hostname: "firebasestorage.googleapis.com" },
      { hostname: "storage.googleapis.com" },
    ],
  },
  async headers() {
    const allowedParentUrl = process.env.ALLOWED_PARENT_URL;

    return [
      {
        source: "/:path*",
        headers: [
          {
            key: "Content-Security-Policy",
            value: `frame-ancestors 'self' ${allowedParentUrl} http://localhost:3000`,
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          {
            key: "X-XSS-Protection",
            value: "1; mode=block",
          },
        ],
      },
    ];
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
