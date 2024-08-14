import { Skeleton } from "@/components/ui/skeleton";

const SkeletonDisplay = () => {
  return (
    <div className="flex size-full flex-col gap-2 overflow-hidden">
      <div className={`relative h-[85%] w-full overflow-hidden rounded-lg`}>
        <Skeleton className="size-full" />
      </div>
      <div className="h-[15%] w-full py-2">
        <Skeleton className="size-full rounded-full" />
      </div>
    </div>
  );
};

export default SkeletonDisplay;
