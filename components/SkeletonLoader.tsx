import React from "react";

const SkeletonLoader = ({ type }: { type: string }) => {
  // Implement different skeleton layouts based on the type
  switch (type) {
    case "partners":
      return (
        <div className="h-full w-full animate-pulse rounded-lg bg-gray-700"></div>
      );
    case "spotlight":
      return (
        <div className="h-full w-full animate-pulse rounded-lg bg-gray-700"></div>
      );
    // Add more cases for other dashboard item types
    default:
      return (
        <div className="h-full w-full animate-pulse rounded-lg bg-gray-700"></div>
      );
  }
};

export default SkeletonLoader;
